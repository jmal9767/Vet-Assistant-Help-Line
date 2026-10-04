/**
 * Paws & Whiskers Care Line intake relay.
 * Website submissions are saved to CloudKit. Optional files are stored in a
 * private R2 bucket and exposed only through signed, expiring download URLs.
 */

import applePayDomainAssociation from "./apple-developer-merchantid-domain-association.txt";

const MAX_LENGTHS = {
  name: 100, email: 200, phone: 40, preferredReply: 40, requestedService: 120,
  petName: 100, species: 60, age: 60, breed: 100, sex: 20, reproductiveStatus: 40,
  weight: 40, category: 80, urgency: 80, symptomOnset: 120, symptomTrend: 60,
  appetite: 60, drinking: 60, urination: 80, stool: 80, energy: 80, vomiting: 100,
  medicalHistory: 1500, currentMedications: 1500, actionsTaken: 1500, question: 4000,
  attachmentSummary: 4000, sourceChannel: 80, conversationStatus: 80,
  paymentStatus: 40, paymentMethod: 80, paymentAmount: 40, paymentLink: 500,
  signedConsentName: 100, signedConsentAt: 80,
};
const MAX_FILES = 4;
const MAX_FILE_BYTES = 10 * 1024 * 1024;
const MAX_TOTAL_BYTES = 40 * 1024 * 1024;
const ATTACHMENT_LINK_SECONDS = 30 * 24 * 60 * 60;

export default {
  async fetch(request, env) {
    try { return await handleRequest(request, env); }
    catch {
      return json({ error: "The service is temporarily unavailable. Please try again shortly." }, 503, corsHeaders(request, env));
    }
  },
};

async function handleRequest(request, env) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/petassist/")) return handlePetAssist(request, env, url);

    if (request.method === "GET" && url.pathname === "/.well-known/apple-developer-merchantid-domain-association") {
      return new Response(applePayDomainAssociation, {
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=3600" },
      });
    }

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
    if (body.acceptedCommunicationPolicy !== "yes") return json({ error: "Please accept the communication policy." }, 400, cors);
    const moderation = moderateClientMessage(body.question);
    if (moderation.blocked) {
      return json({ error: "This message cannot be submitted as written because it appears to violate the communication policy. Please revise it and try again." }, 400, cors);
    }
    const fields = validatedFields(body);
    if (fields.error) return json({ error: fields.error }, 400, cors);

    const fileError = validateFiles(uploadedFiles);
    if (fileError) return json({ error: fileError }, 413, cors);
    if (uploadedFiles.length && (!env.ATTACHMENTS_BUCKET || !env.ATTACHMENT_SIGNING_SECRET)) {
      return json({ error: "Private file uploads are temporarily unavailable. Remove the files and try again." }, 503, cors);
    }

    const storedFiles = await storeAttachments(uploadedFiles, request, env);
    if (storedFiles.length) fields.attachmentSummary = storedFiles.map(formatStoredFile).join("\n");

    let result;
    try {
      result = await saveQuestionToCloudKit(env, cloudKitCreateBody(fields));
    } catch (error) {
      if (storedFiles.length) await env.ATTACHMENTS_BUCKET.delete(storedFiles.map(file => file.key));
      throw error;
    }
    if (!result.ok) {
      if (storedFiles.length) await env.ATTACHMENTS_BUCKET.delete(storedFiles.map(file => file.key));
      return json({ error: "Could not save the question" }, 502, cors);
    }

    const checkoutURL = fields.paymentStatus === "Payment requested" && fields.paymentMethod === "PayPal or Apple Pay" && result.recordName
      ? `${url.origin}/pay?question=${encodeURIComponent(result.recordName)}`
      : "";
    if (checkoutURL) {
      // Intake is already committed; optional link enrichment must not invite a duplicate submission.
      try { await updateQuestionPayment(env, result.recordName, { paymentLink: checkoutURL }); }
      catch { console.error("Checkout link enrichment unavailable"); }
    }
    return json({ ok: true, recordName: result.recordName, checkoutURL }, 200, cors);
}

function moderateClientMessage(message) {
  const text = String(message || "").toLowerCase();
  // Deliberately narrow: block explicit threats/severe harassment, not ordinary profanity
  // or strong language describing the animal's condition.
  const severePatterns = [
    /\b(i('| a)?m going to|i will|gonna) (kill|hurt|shoot|stab|attack) (you|u)\b/,
    /\bkill yourself\b/,
    /\b(i know where you live|i('| a)?ll find you)\b/,
    /\b(send|show) (me )?(nudes|naked pictures)\b/
  ];
  return { blocked: severePatterns.some((pattern) => pattern.test(text)) };
}

function validatedFields(body) {
  const fields = {};
  const optional = new Set(["age", "breed", "weight", "medicalHistory", "currentMedications", "actionsTaken", "phone", "preferredReply", "requestedService", "petName", "urgency", "attachmentSummary", "paymentMethod", "paymentAmount", "paymentLink", "signedConsentName", "signedConsentAt"]);
  for (const key of Object.keys(MAX_LENGTHS)) {
    const value = String(body[key] ?? "").trim().slice(0, MAX_LENGTHS[key]);
    if (!value && !optional.has(key) && !["sourceChannel", "conversationStatus", "paymentStatus"].includes(key)) {
      return { error: `Missing field: ${key}` };
    }
    fields[key] = value;
  }
  if (!/^\S+@\S+\.\S+$/.test(fields.email)) return { error: "Please enter a valid email address." };
  if (!["Dog", "Cat"].includes(fields.species)) return { error: "This service accepts questions about dogs and cats only." };
  if (!fields.signedConsentName || !fields.signedConsentAt || !Number.isFinite(Date.parse(fields.signedConsentAt))) return { error: "Please type your name to sign the consent statement." };
  if (!["Female", "Male", "Unknown"].includes(fields.sex)) return { error: "Please select the dog or cat's sex." };
  if (!["Spayed", "Neutered", "Not spayed or neutered", "Unknown"].includes(fields.reproductiveStatus)) {
    return { error: "Please select the spay or neuter status." };
  }
  const services = {
    "Quick Question — Email · $5": { reply: "Email", amount: "$5" },
    "Quick Question — Text · $5": { reply: "Text message", amount: "$5" },
    "Detailed Guidance — Email · $10": { reply: "Email", amount: "$10" },
    "Detailed Guidance — Text · $10": { reply: "Text message", amount: "$10" },
    "Phone Support · $20": { reply: "Phone call", amount: "$20" },
    "Free Community Support — Email": { reply: "Email", amount: "$0", community: true },
    "Free Community Support — Text": { reply: "Text message", amount: "$0", community: true },
  };
  fields.requestedService = fields.requestedService
    .replace("Community Access — Email · $0", "Free Community Support — Email")
    .replace("Community Access — Text · $0", "Free Community Support — Text");
  const selectedService = services[fields.requestedService];
  if (!selectedService) return { error: "The service menu may have changed. Reload the care-line page and choose a current option." };
  fields.preferredReply = selectedService.reply;
  if (["Text message", "Phone call"].includes(fields.preferredReply) && fields.phone.replace(/\D/g, "").length < 7) {
    return { error: "Please enter a valid phone number for text or phone service." };
  }
  fields.urgency ||= "Not specified";
  if (fields.urgency === "I may need an emergency vet") {
    return { error: "Please contact an emergency veterinarian now instead of submitting a paid request." };
  }
  if (fields.urination === "Not urinating" || fields.vomiting === "Repeated retching with little or nothing coming up") {
    return { error: "This answer may describe an emergency. Please contact an emergency veterinarian now instead of submitting a paid request." };
  }
  fields.sourceChannel = "Website";
  fields.conversationStatus = "Needs response";
  fields.paymentStatus = selectedService.community ? "No payment required" : "Payment requested";
  if (selectedService.community) {
    fields.paymentMethod = "Free Community Support";
  } else if (fields.paymentMethod !== "PayPal or Apple Pay") {
    return { error: "Paid requests use PayPal or Apple Pay checkout. Reload the page to use the current payment options." };
  }
  fields.paymentAmount = selectedService.amount;
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
  if (total > MAX_TOTAL_BYTES) return "The combined files must be 40 MB or less.";
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
  return new Response("<Response><Message>Thanks — your message reached the Paws & Whiskers Care Line.</Message></Response>", {
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
    ? `<Response><Say>Connecting you to the Paws & Whiskers Care Line.</Say><Dial${callerID ? ` callerId="${escapeXML(callerID)}"` : ""}>${escapeXML(operatorPhone)}</Dial></Response>`
    : "<Response><Say>The care line phone relay is not configured. Please use the website.</Say></Response>";
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
    age: "Not given", breed: "Not given", sex: "Unknown", reproductiveStatus: "Unknown", weight: "Not given",
    category: "Other", urgency: "Not specified", symptomOnset: "Not given", symptomTrend: "Not applicable / general question",
    appetite: "Not sure / not applicable", drinking: "Not sure / not applicable", urination: "Not sure / not applicable",
    stool: "Not sure / not applicable", energy: "Not sure / not applicable", vomiting: "Not sure / not applicable",
    medicalHistory: "None reported", currentMedications: "None reported", actionsTaken: "None reported", question: "",
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
    breed: { value: fields.breed || "Not given" }, sex: { value: fields.sex || "Unknown" },
    reproductiveStatus: { value: fields.reproductiveStatus || "Unknown" }, weight: { value: fields.weight || "Not given" },
    category: { value: fields.category }, urgency: { value: fields.urgency }, symptomOnset: { value: fields.symptomOnset || "Not given" },
    symptomTrend: { value: fields.symptomTrend || "Not applicable / general question" }, appetite: { value: fields.appetite || "Not sure / not applicable" },
    drinking: { value: fields.drinking || "Not sure / not applicable" }, urination: { value: fields.urination || "Not sure / not applicable" },
    stool: { value: fields.stool || "Not sure / not applicable" }, energy: { value: fields.energy || "Not sure / not applicable" },
    vomiting: { value: fields.vomiting || "Not sure / not applicable" }, medicalHistory: { value: fields.medicalHistory || "None reported" },
    currentMedications: { value: fields.currentMedications || "None reported" }, actionsTaken: { value: fields.actionsTaken || "None reported" },
    question: { value: fields.question },
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
  const requestData = JSON.parse(requestBody);
  for (let attempt = 0; attempt <= Object.keys(MAX_LENGTHS).length; attempt++) {
  requestBody = JSON.stringify(requestData);
  const headers = await signedHeaders(env, path, requestBody);
  const response = await fetch(`https://api.apple-cloudkit.com${path}`, { method: "POST", headers, body: requestBody });
  const result = await response.json();
  const record = result.records?.find((item) => !item.serverErrorCode);
  if (!response.ok || !record || result.records?.some(item => item.serverErrorCode)) {
    const failures = [result, ...(result.records || [])].filter(item => item.serverErrorCode);
    const reasons = failures.map(item => String(item.reason || '')).join(' ');
    const missingFields = Object.keys(MAX_LENGTHS).filter(name => name !== 'question' && failures.some(item => item.serverErrorCode === 'BAD_REQUEST' && new RegExp('\\b'+name+'\\b').test(String(item.reason || ''))));
    let migrated = false;
    for (const operation of requestData.operations) {
      const fields = operation.record.fields;
      const toPack = missingFields.filter(name => Object.hasOwn(fields, name));
      if (!toPack.length) continue;
      const existing = !fields.question && operation.record.recordName ? await fetchQuestionFromCloudKit(env, operation.record.recordName) : null;
      const original = String(fields.question?.value ?? existing?.fields?.question?.value ?? '');
      const envelope = intakeEnvelope(original) || { format: 'paws-intake-v1', question: original, details: {} };
      for (const name of toPack) { envelope.details[name] = String(fields[name].value ?? ''); delete fields[name]; }
      fields.question = { value: JSON.stringify(envelope) };
      migrated = true;
    }
    // Preserve unavailable schema fields in the existing question field, rather than dropping client information.
    if (migrated) continue;
    // Log only public schema field names and provider codes, never client values or credentials.
    console.error('CloudKit write rejected', JSON.stringify({ status: response.status, codes: failures.map(item => item.serverErrorCode), fields: Object.keys(MAX_LENGTHS).filter(name => new RegExp('\\b'+name+'\\b').test(reasons)) }));
    return { ok: false, status: response.status, conflict: failures.some(item => item.serverErrorCode === "CONFLICT") };
  }
  return {
    ok: Boolean(record) && !result.records?.some((item) => item.serverErrorCode),
    recordName: record?.recordName || "",
  };
  }
  return { ok: false };
}

function intakeEnvelope(value) {
  try {
    const result = JSON.parse(value);
    return result?.format === 'paws-intake-v1' && typeof result.question === 'string' && result.details && typeof result.details === 'object' && !Array.isArray(result.details) ? result : null;
  } catch { return null; }
}

async function fetchQuestionFromCloudKit(env, recordName) {
  if (recordName.startsWith("petassist-")) return readPetAssistPayment(env, recordName);
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
  if (recordName.startsWith("petassist-")) {
    const object = petAssistObject(env, recordName);
    if (!object) return { ok: false };
    return (await object.fetch("https://booking.invalid/payment", { method: "POST", body: JSON.stringify(values) })).json();
  }
  // Compare-and-save prevents a delayed completion from overwriting a concurrent refund.
  for (let attempt = 0; attempt < 3; attempt++) {
    const current = await fetchQuestionFromCloudKit(env, recordName);
    if (!current?.recordChangeTag) return { ok: false };
    const status = fieldValue(current, "paymentStatus");
    if (values.paymentStatus === "Paid" && !["Payment requested", "Paid"].includes(status)) {
      return { ok: true, paymentStatus: status };
    }
    if (values.paymentStatus === "Partially refunded" && status === "Refunded") {
      return { ok: true, paymentStatus: status };
    }
    const fields = {};
    for (const [key, value] of Object.entries(values)) fields[key] = { value: String(value) };
    const body = JSON.stringify({ operations: [{
      operationType: "update",
      record: { recordType: "Question", recordName, recordChangeTag: current.recordChangeTag, fields },
    }] });
    const result = await saveQuestionToCloudKit(env, body);
    if (!result.conflict) return { ...result, paymentStatus: values.paymentStatus || status };
  }
  return { ok: false };
}

function fieldValue(record, name) {
  const packed = intakeEnvelope(String(record?.fields?.question?.value ?? ''));
  return String(record?.fields?.[name]?.value ?? packed?.details?.[name] ?? "").trim();
}

function paidOffer(record) {
  const amountText = fieldValue(record, "paymentAmount");
  const amount = Number(amountText.replace(/[^0-9.]/g, ""));
  // Honor existing requests from the previous menu without offering them to new clients.
  const isPetAssist = record.recordName.startsWith("petassist-");
  const allowedAmounts = new Set(isPetAssist ? Object.values(PETASSIST_SERVICES).map(service => service.amount) : [5, 10, 20, 30, 35]);
  if (!["Payment requested", "Paid"].includes(fieldValue(record, "paymentStatus")) || !allowedAmounts.has(amount)) return null;
  return {
    amount: amount.toFixed(2),
    service: fieldValue(record, "requestedService") || "Paws & Whiskers Care Line service",
  };
}

async function serveCheckout(url, env) {
  const recordName = url.searchParams.get("question") || "";
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const offer = record && paidOffer(record);
  if (!offer) return checkoutMessage("Payment link unavailable", "This payment request is no longer available. Please contact the care line.", 404);
  if (fieldValue(record, "paymentStatus") === "Paid") return checkoutMessage("Payment received", "This request is already paid. Thank you!", 200);
  if (!env.PAYPAL_CLIENT_ID || !env.PAYPAL_CLIENT_SECRET) {
    return checkoutMessage("Checkout is being connected", "Please contact the care line for a payment link.", 503);
  }

  const safeQuestion = JSON.stringify(recordName).replace(/</g, "\\u003c");
  const safeAmount = JSON.stringify(offer.amount);
  const safeService = escapeHTML(offer.service);
  const brand = recordName.startsWith("petassist-") ? "PetAssist Local" : "Paws & Whiskers Care Line";
  const sdkURL = `https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(env.PAYPAL_CLIENT_ID)}&currency=USD&components=buttons,applepay`;
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Secure payment</title><script src="${sdkURL}"></script><script src="https://applepay.cdn-apple.com/jsapi/1.latest/apple-pay-sdk.js"></script>
<style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f7fa;color:#132238;margin:0}.card{max-width:520px;margin:32px auto;background:white;border-radius:18px;padding:24px;box-shadow:0 10px 35px #13223818}.brand{color:#173f67}h1{font-size:1.6rem}.amount{font-size:2rem;font-weight:800;margin:.35rem 0 1rem}.note{color:#536579;line-height:1.45}#applepay-container{margin:14px 0}apple-pay-button{--apple-pay-button-width:100%;--apple-pay-button-height:48px;--apple-pay-button-border-radius:8px}#status{font-weight:650;margin-top:16px}</style></head><body><main class="card"><div class="brand">🐾 ${brand}</div><h1>${safeService}</h1><div class="amount">$${offer.amount}</div><p class="note">Choose PayPal or Apple Pay. Payment status updates automatically after payment succeeds.</p><div id="paypal-buttons"></div><div id="applepay-container"></div><p id="status" role="status"></p></main>
<script>const question=${safeQuestion}, amount=${safeAmount};
const statusEl=document.getElementById('status');
async function createOrder(){const r=await fetch('/api/paypal/orders',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question})});const d=await r.json();if(!r.ok)throw new Error(d.error||'Could not start payment');return d.id}
async function capture(orderID,method){const r=await fetch('/api/paypal/orders/'+encodeURIComponent(orderID)+'/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question,method})});const d=await r.json();if(!r.ok)throw new Error(d.error||'Could not complete payment');statusEl.textContent=d.status==='Paid'?'Payment received. Thank you!':'Payment status: '+d.status+'. Please contact the care line with any questions.';return d}
if(window.paypal && paypal.Buttons){paypal.Buttons({createOrder,onApprove:d=>capture(d.orderID,'PayPal'),onError:()=>{statusEl.textContent='Payment could not be completed. Please try again.'}}).render('#paypal-buttons').catch(()=>{statusEl.textContent='Checkout could not load. Please reload this page or contact the care line.'})}else{statusEl.textContent='Checkout could not load. Please reload this page or contact the care line.'}
if(window.paypal&&paypal.Applepay&&window.ApplePaySession&&ApplePaySession.canMakePayments()){const applepay=paypal.Applepay();applepay.config().then(c=>{if(!c.isEligible)return;document.getElementById('applepay-container').innerHTML='<apple-pay-button id="applepay-button" buttonstyle="black" type="pay" locale="en-US"></apple-pay-button>';document.getElementById('applepay-button').onclick=()=>{const session=new ApplePaySession(4,{countryCode:c.countryCode,merchantCapabilities:c.merchantCapabilities,supportedNetworks:c.supportedNetworks,currencyCode:'USD',total:{label:'Paws & Whiskers Care Line',type:'final',amount}});session.onvalidatemerchant=e=>applepay.validateMerchant({validationUrl:e.validationURL,displayName:'Paws & Whiskers Care Line'}).then(v=>session.completeMerchantValidation(v.merchantSession)).catch(()=>session.abort());session.onpaymentauthorized=e=>createOrder().then(id=>applepay.confirmOrder({orderId:id,token:e.payment.token,billingContact:e.payment.billingContact}).then(()=>capture(id,'Apple Pay')).then(()=>session.completePayment(ApplePaySession.STATUS_SUCCESS))).catch(()=>session.completePayment(ApplePaySession.STATUS_FAILURE));session.begin()}}).catch(()=>{})}
</script></body></html>`, { headers: securityHTMLHeaders() });
}

async function createPayPalOrder(request, env) {
  const input = await safeJSON(request);
  const recordName = String(input?.question || "");
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const offer = record && paidOffer(record);
  if (!offer) return json({ error: "Invalid payment request" }, 400);
  if (fieldValue(record, "paymentStatus") === "Paid") return json({ error: "This request is already paid" }, 409);
  const token = await payPalAccessToken(env);
  if (!token) return json({ error: "Payment service is not configured" }, 503);
  const response = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json", "PayPal-Request-Id": await payPalRequestID(`paws:${recordName}`) },
    body: JSON.stringify({ intent: "CAPTURE", purchase_units: [{
      custom_id: recordName,
      invoice_id: `${recordName.startsWith("petassist-") ? "petassist" : "paws"}-${recordName}`.slice(0, 127),
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
  if (!orderResponse.ok || order.purchase_units?.length !== 1 || !offer || unit?.custom_id !== recordName || unit?.amount?.value !== offer.amount || unit?.amount?.currency_code !== "USD") {
    return json({ error: "Payment details did not match" }, 409);
  }

  if (fieldValue(record, "paymentStatus") === "Paid") {
    return completedCapture(order, offer.amount) ? json({ ok: true, status: "Paid" }, 200) : json({ error: "This request is already paid" }, 409);
  }
  const response = order.status === "COMPLETED" ? null : await fetch(`${payPalAPIBase(env)}/v2/checkout/orders/${orderID}/capture`, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", "PayPal-Request-Id": `capture-${orderID}` },
  });
  const result = response ? await response.json() : order;
  const capture = completedCapture(result, offer.amount);
  if ((response && !response.ok) || !capture) return json({ error: "Payment was not completed" }, 502);
  const update = await updateQuestionPayment(env, recordName, { paymentStatus: "Paid", paymentMethod: method });
  if (!update.ok) return json({ error: "Payment succeeded, but the app status could not be refreshed" }, 502);
  return json({ ok: true, status: update.paymentStatus }, 200);
}

async function handlePayPalWebhook(request, env) {
  if (!env.PAYPAL_WEBHOOK_ID) return json({ error: "Webhook not configured" }, 503);
  const event = await safeJSON(request);
  if (!event) return json({ error: "Invalid event" }, 400);
  const token = await payPalAccessToken(env);
  if (!token) return json({ error: "Payment service is unavailable" }, 503);
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
  if (!verifyResponse.ok || verification.verification_status !== "SUCCESS") return json({ error: "Invalid signature" }, 401);
  if (!["PAYMENT.CAPTURE.COMPLETED", "PAYMENT.CAPTURE.REFUNDED", "PAYMENT.CAPTURE.REVERSED"].includes(event.event_type)) return json({ ok: true }, 200);
  let orderID = event.resource?.supplementary_data?.related_ids?.order_id;
  if (!orderID && event.event_type === "PAYMENT.CAPTURE.REFUNDED") {
    // Refund resources identify their capture through the up link, not an order ID.
    const captureID = payPalCaptureReference(event.resource, env);
    if (captureID) {
      const captureResponse = await fetch(`${payPalAPIBase(env)}/v2/payments/captures/${captureID}`, { headers: { Authorization: `Bearer ${token}` } });
      if (!captureResponse.ok) return json({ error: "Payment lookup failed" }, 502);
      const capture = await captureResponse.json();
      orderID = capture.supplementary_data?.related_ids?.order_id;
    }
  }
  if (!orderID || !/^[A-Z0-9]{1,20}$/.test(orderID)) return json({ error: "Payment order reference is unavailable" }, 502);
  const orderResponse = await fetch(`${payPalAPIBase(env)}/v2/checkout/orders/${orderID}`, { headers: { Authorization: `Bearer ${token}` } });
  const order = await orderResponse.json();
  if (!orderResponse.ok) return json({ error: "Payment lookup failed" }, 502);
  const recordName = order.purchase_units?.[0]?.custom_id;
  if (!recordName || order.purchase_units?.length !== 1) return json({ error: "Payment details did not match" }, 409);
  const record = await fetchQuestionFromCloudKit(env, recordName);
  if (!record) return json({ error: "Payment record not found" }, 503);
  const amount = Number(fieldValue(record, "paymentAmount").replace(/[^0-9.]/g, "")).toFixed(2);
  if (order.purchase_units[0].amount?.value !== amount || order.purchase_units[0].amount?.currency_code !== "USD") return json({ error: "Payment details did not match" }, 409);
  if (event.event_type === "PAYMENT.CAPTURE.COMPLETED") {
    if (!["Payment requested", "Paid"].includes(fieldValue(record, "paymentStatus"))) return json({ ok: true }, 200);
    if (!completedCapture(order, amount)) return json({ error: "Payment details did not match" }, 409);
    const currentMethod = fieldValue(record, "paymentMethod");
    const update = await updateQuestionPayment(env, recordName, { paymentStatus: "Paid", paymentMethod: currentMethod === "Apple Pay" ? "Apple Pay" : "PayPal or Apple Pay" });
    if (!update.ok) return json({ error: "Payment record could not be updated" }, 503);
    return json({ ok: true }, 200);
  }
  const partial = order.purchase_units[0].payments?.captures?.some(capture => capture.status === "PARTIALLY_REFUNDED");
  const update = await updateQuestionPayment(env, recordName, { paymentStatus: partial ? "Partially refunded" : "Refunded" });
  if (!update.ok) return json({ error: "Payment record could not be updated" }, 503);
  return json({ ok: true }, 200);
}

function payPalCaptureReference(resource, env) {
  const allowedHosts = env.PAYPAL_ENVIRONMENT === "live"
    ? ["api.paypal.com", "api-m.paypal.com"] : ["api.sandbox.paypal.com", "api-m.sandbox.paypal.com"];
  for (const link of resource?.links || []) {
    if (link.rel !== "up") continue;
    try {
      const url = new URL(link.href);
      if (url.protocol !== "https:" || !allowedHosts.includes(url.hostname) || url.port || url.username || url.password || url.search || url.hash) continue;
      const match = /^\/v2\/payments\/captures\/([A-Z0-9]{1,20})$/.exec(url.pathname);
      if (match) return match[1];
    } catch {}
  }
  return null;
}

function completedCapture(order, amount) {
  const units = order.purchase_units;
  const captures = units?.[0]?.payments?.captures;
  return units?.length === 1 && captures?.length === 1 && captures[0].status === "COMPLETED"
    && captures[0].amount?.currency_code === "USD" && captures[0].amount?.value === amount
    ? captures[0] : null;
}

async function payPalRequestID(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("").slice(0, 32);
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
  const keys = [];
  try {
    for (const file of files) {
      const id = crypto.randomUUID();
      const key = `questions/${new Date().toISOString().slice(0, 10)}/${id}`;
      keys.push(key);
      await env.ATTACHMENTS_BUCKET.put(key, file.stream(), {
        httpMetadata: { contentType: file.type || "application/octet-stream" },
        customMetadata: { fileName: sanitizeFileName(file.name || "attachment") },
      });
      const expires = Math.floor(Date.now() / 1000) + ATTACHMENT_LINK_SECONDS;
      const signature = await signAttachment(key, expires, env);
      const url = `${origin}/attachments/${encodeURIComponent(key)}?expires=${expires}&signature=${signature}`;
      stored.push({ key, name: file.name, type: file.type || "unknown type", size: file.size, url });
    }
    return stored;
  } catch (error) {
    if (keys.length) await env.ATTACHMENTS_BUCKET.delete(keys);
    throw error;
  }
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
  const allowedOrigins = String(env.ALLOWED_ORIGIN || "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
  return allowedOrigins.includes(origin);
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

const PETASSIST_SERVICES = {
  nailTrim: { title: "Nail Trim", amount: 35 },
  medAdmin: { title: "Medication Administration", amount: 45 },
  labCollection: { title: "Lab Sample Collection", amount: 55 },
  wellnessCheck: { title: "Wellness Check", amount: 65 },
};
function petAssistObject(env, recordName) {
  return /^petassist-[a-f0-9]{32}$/.test(recordName) && env.PETASSIST_PAYMENTS
    ? env.PETASSIST_PAYMENTS.get(env.PETASSIST_PAYMENTS.idFromName(recordName)) : null;
}
async function readPetAssistPayment(env, recordName) {
  const object = petAssistObject(env, recordName);
  return object ? (await object.fetch("https://booking.invalid/record")).json() : null;
}
function petAssistReceipt(record, requestURL) {
  const token = record.recordName.slice("petassist-".length);
  return { token, service: fieldValue(record,"requestedService"), amount: fieldValue(record,"paymentAmount"), status: fieldValue(record,"paymentStatus"), method: fieldValue(record,"paymentMethod"), checkoutURL: `${new URL(requestURL).origin}/petassist/pay?token=${token}` };
}
async function handlePetAssist(request, env, url) {
  const cors = { ...corsHeaders(request, env), "Access-Control-Allow-Methods": "GET, POST, OPTIONS", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" };
  if (request.headers.has("Origin") && !isAllowedOrigin(request, env)) return json({ error: "Origin not allowed" }, 403, cors);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (!env.PETASSIST_PAYMENTS) return json({ error: "PetAssist payments are being connected" }, 503, cors);
  if (request.method === "POST" && url.pathname === "/petassist/bookings") {
    if (!(await allowIntakeRequest(request, env))) return json({ error: "Please wait before trying again" }, 429, cors);
    if (Number(request.headers.get("Content-Length") || 0) > 4096) return json({ error: "Request too large" }, 413, cors);
    const input = await safeJSON(request);
    const service = Object.hasOwn(PETASSIST_SERVICES, input?.service || "") ? PETASSIST_SERVICES[input.service] : null;
    if (!service || !/^[a-f0-9]{32}$/.test(input?.token || "")) return json({ error: "Invalid booking" }, 400, cors);
    const recordName = `petassist-${input.token}`;
    const object = petAssistObject(env, recordName);
    const created = await object.fetch("https://booking.invalid/create", { method: "POST", body: JSON.stringify({recordName, serviceID:input.service, service:service.title, amount:service.amount}) });
    if (!created.ok) return json({ error: "The booking details changed. Create a new booking." }, 409, cors);
    return json(petAssistReceipt(await created.json(), request.url), 200, cors);
  }
  const token = url.pathname === "/petassist/pay" ? url.searchParams.get("token") : url.pathname.match(/^\/petassist\/bookings\/([a-f0-9]{32})$/)?.[1];
  if (request.method !== "GET" || !/^[a-f0-9]{32}$/.test(token || "")) return json({ error: "Not found" }, 404, cors);
  const record = await readPetAssistPayment(env, `petassist-${token}`);
  if (!record) return json({ error: "Booking not found" }, 404, cors);
  if (url.pathname === "/petassist/pay") {
    if (["Refunded","Partially refunded"].includes(fieldValue(record,"paymentStatus"))) return checkoutMessage("Payment refunded", "This payment has been refunded. Contact info@bayareaapps.com with any questions.", 200);
    const checkout = new URL(request.url); checkout.search = `?question=petassist-${token}`;
    return serveCheckout(checkout, env);
  }
  return json(petAssistReceipt(record, request.url), 200, cors);
}
export class PetAssistPayments {
  constructor(state) { this.state = state; }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (path === "/record") return Response.json(await this.state.storage.get("record") || null);
    const input = await request.json();
    return this.state.storage.transaction(async txn => {
      let record = await txn.get("record");
      if (path === "/create") {
        if (record) return Response.json(record, { status: record.serviceID === input.serviceID ? 200 : 409 });
        const fields = Object.fromEntries(Object.entries({ requestedService:input.service, paymentAmount:`$${input.amount}`, paymentStatus:"Payment requested", paymentMethod:"PayPal or Apple Pay", sourceChannel:"PetAssist Local" }).map(([key,value])=>[key,{value}]));
        record = { recordName:input.recordName, recordType:"PetAssistPayment", recordChangeTag:"1", serviceID:input.serviceID, fields };
        await txn.put("record",record); return Response.json(record);
      }
      if (path !== "/payment" || !record) return Response.json({ok:false});
      const current = record.fields.paymentStatus.value;
      const incoming = input.paymentStatus;
      if (!['Paid','Refunded','Partially refunded'].includes(incoming)) return Response.json({ok:false});
      if ((incoming === 'Paid' && !['Payment requested','Paid'].includes(current)) || (incoming === 'Partially refunded' && current === 'Refunded')) return Response.json({ok:true,paymentStatus:current});
      record.fields.paymentStatus = {value:incoming};
      if (input.paymentMethod) record.fields.paymentMethod = {value:String(input.paymentMethod)};
      record.recordChangeTag = String(Number(record.recordChangeTag)+1);
      await txn.put('record',record);
      return Response.json({ok:true,paymentStatus:incoming});
    });
  }
}
