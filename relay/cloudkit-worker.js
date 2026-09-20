/**
 * Vet Assistant Help Line intake relay.
 * Website submissions are saved to CloudKit. Optional files are stored in a
 * private R2 bucket and exposed only through signed, expiring download URLs.
 */

const MAX_LENGTHS = {
  name: 100, email: 200, phone: 40, preferredReply: 40, requestedService: 120,
  petName: 100, species: 60, age: 60, category: 80, urgency: 80, question: 4000,
  attachmentSummary: 4000, sourceChannel: 80, conversationStatus: 80,
  paymentStatus: 40, paymentMethod: 80, paymentAmount: 40, paymentLink: 500,
  signedConsentName: 100, signedConsentAt: 80,
};
const MAX_FILES = 4;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_TOTAL_BYTES = 30 * 1024 * 1024;
const ATTACHMENT_LINK_SECONDS = 30 * 24 * 60 * 60;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname.startsWith("/attachments/")) {
      return serveAttachment(url, env);
    }
    if (request.method === "GET" && url.pathname === "/pay") {
      return serveCheckout(url, env);
    }
    if (request.method === "POST" && url.pathname === "/api/paypal/orders") {
      return createPayPalOrder(request, env);
    }
    if (request.method === "POST" && /^\/api\/paypal\/orders\/[^/]+\/capture$/.test(url.pathname)) {
      return capturePayPalOrder(request, env, url.pathname.split("/")[4]);
    }
    if (request.method === "POST" && url.pathname === "/paypal/webhook") {
      return handlePayPalWebhook(request, env);
    }

    const cors = corsHeaders(request, env);
    if (request.method === "OPTIONS") {
      if (!isAllowedOrigin(request, env)) return json({ error: "Origin not allowed" }, 403, cors);
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405, cors);

    if (url.pathname === "/twilio/sms") return handleTwilioSMS(request, env, cors);
    if (url.pathname === "/twilio/voice") return handleTwilioVoice(request, env);
    if (url.pathname === "/sendgrid/inbound") return handleInboundEmail(request, env, cors);
    if (url.pathname !== "/" && url.pathname !== "/intake") {
      return json({ error: "Not found" }, 404, cors);
    }

    if (!isAllowedOrigin(request, env)) return json({ error: "Origin not allowed" }, 403, cors);
    if (!(await allowIntakeRequest(request, env))) {
      return json({ error: "Too many submissions. Please wait a few minutes and try again." }, 429, cors);
    }

    const contentLength = Number(request.headers.get("Content-Length") || 0);
    if (contentLength > MAX_TOTAL_BYTES + 1_000_000) {
      return json({ error: "The submission is too large." }, 413, cors);
    }

    let body;
    let uploadedFiles = [];
    try {
      const contentType = request.headers.get("Content-Type") || "";
      if (contentType.includes("multipart/form-data")) {
        const form = await request.formData();
        body = Object.fromEntries([...form.entries()].filter((entry) => typeof entry[1] === "string"));
        uploadedFiles = [...form.getAll("attachments")].filter((file) => file instanceof File && file.size > 0);
      } else {
        body = await request.json();
      }
    } catch {
      return json({ error: "Invalid submission" }, 400, cors);
    }

    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return json({ error: "Invalid submission" }, 400, cors);
    }
    if (body.website) return json({ ok: true }, 200, cors);

    if (body.acceptedTerms !== "yes") return json({ error: "Please accept the service terms and privacy notice." }, 400, cors);
    const fields = validatedFields(body);
    if (fields.error) return json({ error: fields.error }, 400, cors);

    const fileError = validateFiles(uploadedFiles);
    if (fileError) return json({ error: fileError }, 413, cors);
    if (uploadedFiles.length && (!env.ATTACHMENTS_BUCKET || !env.ATTACHMENT_SIGNING_SECRET)) {
      return json({ error: "Private file uploads are temporarily unavailable. Remove the files and try again." }, 503, cors);
    }

    const storedFiles = await storeAttachments(uploadedFiles, request, env);
    if (storedFiles.length) fields.attachmentSummary = storedFiles.map(formatStoredFile).join("\n");

    const result = await saveQuestionToCloudKit(env, cloudKitCreateBody(fields));
    if (!result.ok) return json({ error: "Could not save the question" }, 502, cors);

    return json({ ok: true }, 200, cors);
  },
};

function validatedFields(body) {
  const fields = {};
  const optional = new Set(["age", "phone", "preferredReply", "requestedService", "petName", "urgency", "attachmentSummary", "paymentMethod", "paymentAmount", "paymentLink", "signedConsentName", "signedConsentAt"]);
  for (const key of Object.keys(MAX_LENGTHS)) {
    const value = String(body[key] ?? "").trim().slice(0, MAX_LENGTHS[key]);
    if (!value && !optional.has(key) && !["sourceChannel", "conversationStatus", "paymentStatus"].includes(key)) {
      return { error: `Missing field: ${key}` };
    }
    fields[key] = value;
  }
  if (!/^\S+@\S+\.\S+$/.test(fields.email)) return { error: "Please enter a valid email address." };
  fields.preferredReply ||= fields.phone ? "Text message" : "Email";
  if (["Text message", "Phone call"].includes(fields.preferredReply) && fields.phone.replace(/\D/g, "").length < 7) {
    return { error: "Please enter a valid phone number for text or phone service." };
  }
  fields.requestedService ||= fields.preferredReply;
  fields.urgency ||= "Not specified";
  fields.sourceChannel = "Website";
  fields.conversationStatus = "Needs response";
  fields.paymentStatus = "Reviewing";
  fields.paymentMethod ||= "Client has no preference";
  fields.paymentAmount = "Not set";
  fields.paymentLink = "";
  return fields;
}

function validateFiles(files) {
  if (files.length > MAX_FILES) return `Please upload ${MAX_FILES} files or fewer.`;
  let total = 0;
  for (const file of files) {
    total += file.size;
    if (file.size > MAX_FILE_BYTES) return `${file.name} is too large. Keep each file under 10 MB.`;
  }
  if (total > MAX_TOTAL_BYTES) return "The combined files must be under 30 MB.";
  return null;
}

async function allowIntakeRequest(request, env) {
  if (!env.INTAKE_RATE_LIMITER) return true;
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const result = await env.INTAKE_RATE_LIMITER.limit({ key: ip });
  return result.success;
}

async function handleTwilioSMS(request, env, cors) {
  if (!authorizedWebhook(request, env)) return json({ error: "Webhook is not configured" }, 503, cors);
  const form = await request.formData();
  const from = String(form.get("From") || "").trim();
  const body = String(form.get("Body") || "").trim();
  const fields = baseCommunicationFields({
    name: "Text client", phone: from, preferredReply: "Text message",
    requestedService: "Text response", question: body || "Client sent an empty text message.",
    sourceChannel: "SMS", conversationStatus: "Client text received",
  });
  const result = await saveQuestionToCloudKit(env, cloudKitCreateBody(fields));
  if (!result.ok) return json({ error: "Could not save SMS" }, 502, cors);
  return new Response("<Response><Message>Thanks — your message reached the Vet Assistant Help Line.</Message></Response>", {
    status: 200, headers: { "Content-Type": "text/xml", ...cors },
  });
}

async function handleInboundEmail(request, env, cors) {
  if (!authorizedWebhook(request, env)) return json({ error: "Webhook is not configured" }, 503, cors);
  const form = await request.formData();
  const from = String(form.get("from") || form.get("sender") || "").trim();
  const subject = String(form.get("subject") || "Email question").trim();
  const text = String(form.get("text") || "").trim();
  const fields = baseCommunicationFields({
    name: displayNameFromEmail(from) || "Email client", email: emailAddressFromHeader(from),
    preferredReply: "Email", requestedService: "Email response",
    category: subject.slice(0, MAX_LENGTHS.category), question: text || subject,
    sourceChannel: "Email", conversationStatus: "Client email received",
  });
  const result = await saveQuestionToCloudKit(env, cloudKitCreateBody(fields));
  if (!result.ok) return json({ error: "Could not save email" }, 502, cors);
  return json({ ok: true }, 200, cors);
}

function handleTwilioVoice(request, env) {
  if (!authorizedWebhook(request, env)) return new Response("Webhook is not configured", { status: 503 });
  const operatorPhone = env.OPERATOR_PHONE || "";
  const callerID = env.TWILIO_CALLER_ID || "";
  const body = operatorPhone
    ? `<Response><Say>Connecting you to the Vet Assistant Help Line.</Say><Dial${callerID ? ` callerId="${escapeXML(callerID)}"` : ""}>${escapeXML(operatorPhone)}</Dial></Response>`
    : "<Response><Say>The help line phone relay is not configured. Please use the website.</Say></Response>";
  return new Response(body, { status: 200, headers: { "Content-Type": "text/xml" } });
}

function authorizedWebhook(request, env) {
  if (!env.WEBHOOK_SECRET) return false;
  const authorization = request.headers.get("Authorization") || "";
  return constantTimeEqual(authorization, `Bearer ${env.WEBHOOK_SECRET}`);
}

function constantTimeEqual(left, right) {
  const a = new TextEncoder().encode(left);
  const b = new TextEncoder().encode(right);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index];
  return difference === 0;
}

function baseCommunicationFields(overrides) {
  return {
    name: "", email: "", phone: "", preferredReply: "Email",
    requestedService: "Email response", petName: "", species: "Unknown",
    age: "Not given", category: "Other", urgency: "Not specified", question: "",
    attachmentSummary: "", sourceChannel: "Website", conversationStatus: "Needs response",
    paymentStatus: "Reviewing", paymentMethod: "Client has no preference",
    paymentAmount: amountFromService(overrides.requestedService || ""), paymentLink: "",
    signedConsentName: "", signedConsentAt: "", ...overrides,
  };
}

function cloudKitCreateBody(fields) {
  return JSON.stringify({ operations: [{ operationType: "create", record: { recordType: "Question", fields: {
    name: { value: fields.name }, email: { value: fields.email }, phone: { value: fields.phone || "" },
    preferredReply: { value: fields.preferredReply }, requestedService: { value: fields.requestedService },
    petName: { value: fields.petName || "" }, species: { value: fields.species }, age: { value: fields.age || "Not given" },
    category: { value: fields.category }, urgency: { value: fields.urgency }, question: { value: fields.question },
    attachmentSummary: { value: fields.attachmentSummary || "" }, sourceChannel: { value: fields.sourceChannel || "Website" },
    conversationStatus: { value: fields.conversationStatus || "Needs response" }, paymentStatus: { value: fields.paymentStatus },
    paymentMethod: { value: fields.paymentMethod || "Client has no preference" }, paymentAmount: { value: fields.paymentAmount },
    paymentLink: { value: fields.paymentLink || "" }, signedConsentName: { value: fields.signedConsentName || "" },
    signedConsentAt: { value: fields.signedConsentAt || "" }, status: { value: "new" },
    submittedAt: { value: Date.now(), type: "TIMESTAMP" },
  } } }] });
}

async function saveQuestionToCloudKit(env, requestBody) {
  const path = `/database/1/${env.CLOUDKIT_CONTAINER}/${env.CLOUDKIT_ENVIRONMENT}/public/records/modify`;
  const headers = await signedHeaders(env, path, requestBody);
  const response = await fetch(`https://api.apple-cloudkit.com${path}`, { method: "POST", headers, body: requestBody });
  if (!response.ok) return { ok: false, status: response.status };
  const result = await response.json();
  return { ok: !result.records?.some((record) => record.serverErrorCode) };
}

async function fetchQuestionFromCloudKit(env, recordName) {
  if (!/^[A-Za-z0-9_.:-]{1,255}$/.test(recordName)) return null;
  const path = `/database/1/${env.CLOUDKIT_CONTAINER}/${env.CLOUDKIT_ENVIRONMENT}/public/records/lookup`;
  const body = JSON.stringify({ records: [{ recordName }] });
  const headers = await signedHeaders(env, path, body);
  const response = await fetch(`https://api.apple-cloudkit.com${path}`, { method: "POST", headers, body });
  if (!response.ok) return null;
  const result = await response.json();
  const record = result.records?.[0];
  return record && !record.serverErrorCode ? record : null;
}

async function updateQuestionPayment(env, recordName, values) {
  const fields = {};
  for (const [key, value] of Object.entries(values)) fields[key] = { value: String(value) };
  const body = JSON.stringify({ operations: [{
    operationType: "forceUpdate",
    record: { recordType: "Question", recordName, fields },
  }] });
  return saveQuestionToCloudKit(env, body);
}

function fieldValue(record, name) {
  return String(record?.fields?.[name]?.value ?? "").trim();
}

function paidOffer(record) {
  const amountText = fieldValue(record, "paymentAmount");
  const amount = Number(amountText.replace(/[^0-9.]/g, ""));
  const allowedAmounts = new Set([10, 20, 35]);
  if (fieldValue(record, "paymentStatus") !== "Payment requested" || !allowedAmounts.has(amount)) return null;
  return {
    amount: amount.toFixed(2),
    service: fieldValue(record, "requestedService") || "Vet Assistant Help Line service",
  };
}

async function serveCheckout(url, env) {
  const recordName = url.searchParams.get("question") || "";
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const offer = record && paidOffer(record);
  if (!offer) return checkoutMessage("Payment link unavailable", "This payment request is no longer available. Please contact the help line.", 404);
  if (!env.PAYPAL_CLIENT_ID || !env.PAYPAL_CLIENT_SECRET) {
    return checkoutMessage("Checkout is being connected", "Please contact the help line for a payment link.", 503);
  }

  const safeQuestion = JSON.stringify(recordName).replace(/</g, "\\u003c");
  const safeAmount = JSON.stringify(offer.amount);
  const safeService = escapeHTML(offer.service);
  const sdkURL = `https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(env.PAYPAL_CLIENT_ID)}&currency=USD&components=buttons,applepay`;
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Secure payment</title><script src="${sdkURL}"></script><script src="https://applepay.cdn-apple.com/jsapi/1.latest/apple-pay-sdk.js"></script>
<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f7fa;color:#132238;margin:0}.card{max-width:520px;margin:32px auto;background:white;border-radius:18px;padding:24px;box-shadow:0 10px 35px #13223818}.brand{color:#173f67}h1{font-size:1.6rem}.amount{font-size:2rem;font-weight:800;margin:.35rem 0 1rem}.note{color:#536579;line-height:1.45}#applepay-container{margin:14px 0}apple-pay-button{--apple-pay-button-width:100%;--apple-pay-button-height:48px;--apple-pay-button-border-radius:8px}#status{font-weight:650;margin-top:16px}</style></head><body><main class="card"><div class="brand">🐾 Vet Assistant Help Line</div><h1>${safeService}</h1><div class="amount">$${offer.amount}</div><p class="note">Choose PayPal or Apple Pay. Your question will be marked paid automatically after payment succeeds.</p><div id="paypal-buttons"></div><div id="applepay-container"></div><p id="status" role="status"></p></main>
<script>const question=${safeQuestion}, amount=${safeAmount};
const statusEl=document.getElementById('status');
async function createOrder(){const r=await fetch('/api/paypal/orders',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question})});const d=await r.json();if(!r.ok)throw new Error(d.error||'Could not start payment');return d.id}
async function capture(orderID,method){const r=await fetch('/api/paypal/orders/'+encodeURIComponent(orderID)+'/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question,method})});const d=await r.json();if(!r.ok)throw new Error(d.error||'Could not complete payment');statusEl.textContent='Payment received. Thank you!';return d}
paypal.Buttons({createOrder,onApprove:d=>capture(d.orderID,'PayPal'),onError:()=>{statusEl.textContent='Payment could not be completed. Please try again.'}}).render('#paypal-buttons');
if(window.ApplePaySession&&ApplePaySession.canMakePayments()){const applepay=paypal.Applepay();applepay.config().then(c=>{if(!c.isEligible)return;document.getElementById('applepay-container').innerHTML='<apple-pay-button id="applepay-button" buttonstyle="black" type="pay" locale="en-US"></apple-pay-button>';document.getElementById('applepay-button').onclick=()=>{const session=new ApplePaySession(4,{countryCode:c.countryCode,merchantCapabilities:c.merchantCapabilities,supportedNetworks:c.supportedNetworks,currencyCode:'USD',total:{label:'Vet Assistant Help Line',type:'final',amount}});session.onvalidatemerchant=e=>applepay.validateMerchant({validationUrl:e.validationURL,displayName:'Vet Assistant Help Line'}).then(v=>session.completeMerchantValidation(v.merchantSession)).catch(()=>session.abort());session.onpaymentauthorized=e=>createOrder().then(id=>applepay.confirmOrder({orderId:id,token:e.payment.token,billingContact:e.payment.billingContact}).then(()=>capture(id,'Apple Pay')).then(()=>session.completePayment(ApplePaySession.STATUS_SUCCESS))).catch(()=>session.completePayment(ApplePaySession.STATUS_FAILURE));session.begin()}}).catch(()=>{})}
</script></body></html>`, { headers: securityHTMLHeaders() });
}

async function createPayPalOrder(request, env) {
  const input = await safeJSON(request);
  const recordName = String(input?.question || "");
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const offer = record && paidOffer(record);
  if (!offer) return json({ error: "Invalid payment request" }, 400);
  const token = await payPalAccessToken(env);
  if (!token) return json({ error: "Payment service is not configured" }, 503);
  const response = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json", "PayPal-Request-Id": `question-${recordName}` },
    body: JSON.stringify({ intent: "CAPTURE", purchase_units: [{
      custom_id: recordName,
      description: offer.service.slice(0, 127),
      amount: { currency_code: "USD", value: offer.amount },
    }] }),
  });
  const result = await response.json();
  return json(response.ok ? { id: result.id } : { error: "Could not start payment" }, response.ok ? 200 : 502);
}

async function capturePayPalOrder(request, env, orderID) {
  const input = await safeJSON(request);
  const recordName = String(input?.question || "");
  const method = input?.method === "Apple Pay" ? "Apple Pay" : "PayPal";
  const token = await payPalAccessToken(env);
  if (!token || !/^[A-Z0-9]+$/.test(orderID)) return json({ error: "Invalid payment" }, 400);

  const orderResponse = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders/${orderID}`, { headers: { Authorization: `Bearer ${token}` } });
  const order = await orderResponse.json();
  const unit = order.purchase_units?.[0];
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const offer = record && paidOffer(record);
  if (!orderResponse.ok || !offer || unit?.custom_id !== recordName || unit?.amount?.value !== offer.amount || unit?.amount?.currency_code !== "USD") {
    return json({ error: "Payment details did not match" }, 409);
  }

  const response = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders/${orderID}/capture`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "PayPal-Request-Id": `capture-${orderID}` },
  });
  const result = await response.json();
  const capture = result.purchase_units?.[0]?.payments?.captures?.[0];
  if (!response.ok || capture?.status !== "COMPLETED") return json({ error: "Payment was not completed" }, 502);
  const update = await updateQuestionPayment(env, recordName, { paymentStatus: "Paid", paymentMethod: method });
  if (!update.ok) return json({ error: "Payment succeeded, but the app status could not be refreshed" }, 502);
  return json({ ok: true, status: "Paid" }, 200);
}

async function handlePayPalWebhook(request, env) {
  if (!env.PAYPAL_WEBHOOK_ID) return json({ error: "Webhook not configured" }, 503);
  const event = await safeJSON(request);
  if (!event) return json({ error: "Invalid event" }, 400);
  const token = await payPalAccessToken(env);
  const verifyResponse = await fetch(`${payPalAPIBase(env)}/v1/notifications/verify-webhook-signature`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      auth_algo: request.headers.get("PAYPAL-AUTH-ALGO"),
      cert_url: request.headers.get("PAYPAL-CERT-URL"),
      transmission_id: request.headers.get("PAYPAL-TRANSMISSION-ID"),
      transmission_sig: request.headers.get("PAYPAL-TRANSMISSION-SIG"),
      transmission_time: request.headers.get("PAYPAL-TRANSMISSION-TIME"),
      webhook_id: env.PAYPAL_WEBHOOK_ID,
      webhook_event: event,
    }),
  });
  const verification = await verifyResponse.json();
  if (verification.verification_status !== "SUCCESS") return json({ error: "Invalid signature" }, 401);
  if (!["PAYMENT.CAPTURE.REFUNDED", "PAYMENT.CAPTURE.REVERSED"].includes(event.event_type)) return json({ ok: true }, 200);
  const orderID = event.resource?.supplementary_data?.related_ids?.order_id;
  if (!orderID) return json({ ok: true }, 200);
  const orderResponse = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders/${orderID}`, { headers: { Authorization: `Bearer ${token}` } });
  const order = await orderResponse.json();
  const recordName = order.purchase_units?.[0]?.custom_id;
  if (recordName) await updateQuestionPayment(env, recordName, { paymentStatus: "Refunded" });
  return json({ ok: true }, 200);
}

async function payPalAccessToken(env) {
  if (!env.PAYPAL_CLIENT_ID || !env.PAYPAL_CLIENT_SECRET) return null;
  const credentials = btoa(`${env.PAYPAL_CLIENT_ID}:${env.PAYPAL_CLIENT_SECRET}`);
  const response = await fetch(`${payPalAPIBase(env)}/v1/oauth2/token`, {
    method: "POST", headers: { Authorization: `Basic ${credentials}`, "Content-Type": "application/x-www-form-urlencoded" }, body: "grant_type=client_credentials",
  });
  if (!response.ok) return null;
  return (await response.json()).access_token || null;
}

function payPalAPIBase(env) {
  return env.PAYPAL_ENVIRONMENT === "live" ? "https://api-m.paypal.com" : "https://api-m.sandbox.paypal.com";
}

async function safeJSON(request) {
  try { return await request.json(); } catch { return null; }
}

function checkoutMessage(title, message, status) {
  return new Response(`<!doctype html><meta name="viewport" content="width=device-width"><title>${escapeHTML(title)}</title><style>body{font-family:-apple-system,sans-serif;max-width:540px;margin:48px auto;padding:20px;color:#132238}h1{color:#173f67}</style><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p>`, { status, headers: securityHTMLHeaders() });
}

function securityHTMLHeaders() {
  return { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline' https://www.paypal.com https://www.paypalobjects.com https://applepay.cdn-apple.com; frame-src https://www.paypal.com; connect-src 'self' https://www.paypal.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://www.paypalobjects.com" };
}

function escapeHTML(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[character]);
}

async function storeAttachments(files, request, env) {
  const origin = new URL(request.url).origin;
  const stored = [];
  for (const file of files) {
    const id = crypto.randomUUID();
    const key = `questions/${new Date().toISOString().slice(0, 10)}/${id}`;
    await env.ATTACHMENTS_BUCKET.put(key, file.stream(), {
      httpMetadata: { contentType: file.type || "application/octet-stream" },
      customMetadata: { fileName: sanitizeFileName(file.name || "attachment") },
    });
    const expires = Math.floor(Date.now() / 1000) + ATTACHMENT_LINK_SECONDS;
    const signature = await signAttachment(key, expires, env);
    const url = `${origin}/attachments/${encodeURIComponent(key)}?expires=${expires}&signature=${signature}`;
    stored.push({ name: file.name, type: file.type || "unknown type", size: file.size, url });
  }
  return stored;
}

async function serveAttachment(url, env) {
  if (!env.ATTACHMENTS_BUCKET || !env.ATTACHMENT_SIGNING_SECRET) return new Response("Not found", { status: 404 });
  const key = decodeURIComponent(url.pathname.slice("/attachments/".length));
  const expires = Number(url.searchParams.get("expires") || 0);
  const signature = url.searchParams.get("signature") || "";
  if (!key || !Number.isFinite(expires) || expires < Math.floor(Date.now() / 1000)) {
    return new Response("This private file link has expired.", { status: 410 });
  }
  if (!(await verifyAttachmentSignature(key, expires, signature, env))) return new Response("Unauthorized", { status: 401 });
  const object = await env.ATTACHMENTS_BUCKET.get(key);
  if (!object) return new Response("Not found", { status: 404 });
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  const contentType = headers.get("Content-Type") || "application/octet-stream";
  const safeInline = contentType.startsWith("image/") || contentType.startsWith("video/") || contentType === "application/pdf" || contentType === "text/plain";
  headers.set("Content-Disposition", `${safeInline ? "inline" : "attachment"}; filename="${sanitizeFileName(object.customMetadata?.fileName || "attachment")}"`);
  headers.set("Cache-Control", "private, no-store");
  headers.set("X-Content-Type-Options", "nosniff");
  headers.set("Cross-Origin-Resource-Policy", "same-site");
  return new Response(object.body, { headers });
}

async function attachmentKey(env, usages) {
  return crypto.subtle.importKey("raw", new TextEncoder().encode(env.ATTACHMENT_SIGNING_SECRET), { name: "HMAC", hash: "SHA-256" }, false, usages);
}
async function signAttachment(key, expires, env) {
  const cryptoKey = await attachmentKey(env, ["sign"]);
  const bytes = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(`${key}:${expires}`));
  return toBase64URL(new Uint8Array(bytes));
}
async function verifyAttachmentSignature(key, expires, signature, env) {
  try {
    const cryptoKey = await attachmentKey(env, ["verify"]);
    return crypto.subtle.verify("HMAC", cryptoKey, fromBase64URL(signature), new TextEncoder().encode(`${key}:${expires}`));
  } catch { return false; }
}

function formatStoredFile(file) {
  return `${sanitizeFileName(file.name)} (${file.type}, ${Math.ceil(file.size / 1024)} KB) - ${file.url}`;
}
function sanitizeFileName(value) {
  return String(value).replace(/[\\/\r\n"<>]/g, "-").trim().slice(0, 120) || "attachment";
}
function amountFromService(service) {
  const match = String(service).match(/\$\d+/);
  return match ? match[0] : "Confirm";
}
function emailAddressFromHeader(value) {
  const match = String(value).match(/<([^>]+)>/);
  return (match ? match[1] : value).trim();
}
function displayNameFromEmail(value) {
  return String(value).replace(/<[^>]+>/, "").replace(/"/g, "").trim();
}
function escapeXML(value) {
  return String(value).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;");
}
function isAllowedOrigin(request, env) {
  const origin = request.headers.get("Origin") || "";
  return Boolean(env.ALLOWED_ORIGIN && origin === env.ALLOWED_ORIGIN);
}
function corsHeaders(request, env) {
  const origin = isAllowedOrigin(request, env) ? request.headers.get("Origin") : "null";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Vary": "Origin",
  };
}
function json(payload, status, cors = {}) {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json", "X-Content-Type-Options": "nosniff", ...cors } });
}

async function signedHeaders(env, path, requestBody) {
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(requestBody));
  const message = `${date}:${toBase64(bodyHash)}:${path}`;
  const key = await importPrivateKey(env.CLOUDKIT_PRIVATE_KEY);
  const rawSignature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(message));
  return {
    "Content-Type": "application/json",
    "X-Apple-CloudKit-Request-KeyID": env.CLOUDKIT_KEY_ID,
    "X-Apple-CloudKit-Request-ISO8601Date": date,
    "X-Apple-CloudKit-Request-SignatureV1": toBase64(p1363ToDer(new Uint8Array(rawSignature))),
  };
}
async function importPrivateKey(pem) {
  const base64 = pem.replace(/-----BEGIN PRIVATE KEY-----/, "").replace(/-----END PRIVATE KEY-----/, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}
function p1363ToDer(signature) {
  const encode = (bytes) => {
    let first = 0;
    while (first < bytes.length - 1 && bytes[first] === 0) first++;
    let value = bytes.slice(first);
    if (value[0] & 0x80) value = Uint8Array.from([0, ...value]);
    return Uint8Array.from([0x02, value.length, ...value]);
  };
  const r = encode(signature.slice(0, 32));
  const s = encode(signature.slice(32));
  return Uint8Array.from([0x30, r.length + s.length, ...r, ...s]);
}
function toBase64(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}
function toBase64URL(bytes) {
  return toBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function fromBase64URL(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}
