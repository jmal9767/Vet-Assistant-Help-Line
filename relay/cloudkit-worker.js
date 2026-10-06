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
    if (url.pathname.startsWith("/careline/")) return handleCareline(request, env, url);
    if (url.pathname.startsWith("/petassist/")) return handlePetAssist(request, env, url);

    if (request.method === "GET" && url.pathname === "/.well-known/apple-developer-merchantid-domain-association") {
      return new Response(applePayDomainAssociation, {
        headers: { "Content-Type": "application/octet-stream", "Cache-Control": "public, max-age=3600" },
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

    let conversation = null;
    if (body.conversationToken !== undefined || body.conversationAccess !== undefined) {
      if (!/^[a-f0-9]{32}$/.test(body.conversationToken||"") || !/^[a-f0-9]{64}$/.test(body.conversationAccess||"")) return json({error:"Your private conversation could not be verified. Reload and retry."},400,cors);
      if (!env.PETASSIST_PAYMENTS) return json({error:"Private conversations are unavailable. Please retry later."},503,cors);
      conversation = careObject(env,body.conversationToken);
      const previous = await (await conversation.fetch("https://care.invalid/thread")).json();
      if(previous && !await secretMatches(body.conversationAccess,previous.clientAccess)) return json({error:"This private conversation cannot be reused."},409,cors);
      if(previous?.recordName) return careIntakeReceipt(previous.recordName,body.conversationToken,body.conversationAccess,url,env,cors);
      const prepared=await conversation.fetch("https://care.invalid/thread-init",{method:"POST",body:JSON.stringify({clientAccess:body.conversationAccess})});
      if(!prepared.ok)return json({error:"Your private conversation could not be prepared. Please retry."},409,cors);
      fields.question=JSON.stringify({format:"paws-intake-v1",question:fields.question,details:{conversationToken:body.conversationToken}});
    }
    const storedFiles = await storeAttachments(uploadedFiles, request, env);
    if (storedFiles.length) fields.attachmentSummary = storedFiles.map(formatStoredFile).join("\n");

    let result;
    try {
      const payload=JSON.parse(cloudKitCreateBody(fields));
      if(conversation) {
        payload.operations[0].record.recordName="careline-"+body.conversationToken;
        const existing=await fetchQuestionFromCloudKit(env,payload.operations[0].record.recordName);
        if(existing && storedFiles.length)await env.ATTACHMENTS_BUCKET.delete(storedFiles.map(file=>file.key));
        result=existing?{ok:true,recordName:existing.recordName}:await saveQuestionToCloudKit(env,JSON.stringify(payload));
      } else result = await saveQuestionToCloudKit(env,JSON.stringify(payload));
    } catch (error) {
      if (storedFiles.length) await env.ATTACHMENTS_BUCKET.delete(storedFiles.map(file => file.key));
      throw error;
    }
    if (!result.ok) {
      if (storedFiles.length) await env.ATTACHMENTS_BUCKET.delete(storedFiles.map(file => file.key));
      return json({ error: "Could not save the question" }, 502, cors);
    }

    const statusURL = result.recordName ? `${url.origin}/pay?question=${encodeURIComponent(result.recordName)}` : "";
    if(conversation) {
      const bound=await conversation.fetch("https://care.invalid/thread-bind",{method:"POST",body:JSON.stringify({recordName:result.recordName})});
      if(!bound.ok)return json({error:"Your question was saved; retry to recover its private conversation."},503,cors);
      return careIntakeReceipt(result.recordName,body.conversationToken,body.conversationAccess,url,env,cors);
    }
    return json({ ok: true, recordName: result.recordName, statusURL, checkoutURL: "" }, 200, cors);
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
    "Quick Question — Private Message · $10": { reply: "Private website conversation", amount: "$10" },
    "Detailed Guidance — Private Message · $15": { reply: "Private website conversation", amount: "$15" },
    "Free Community Support — Private Message": { reply: "Private website conversation", amount: "$0", community: true },
    "Quick Question — Email · $10": { reply: "Email", amount: "$10" },
    "Quick Question — Text · $10": { reply: "Text message", amount: "$10" },
    "Detailed Guidance — Email · $15": { reply: "Email", amount: "$15" },
    "Detailed Guidance — Text · $15": { reply: "Text message", amount: "$15" },
    "Phone Support · $25": { reply: "Phone call", amount: "$25" },
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
  fields.conversationStatus = selectedService.community ? "Needs response" : "Awaiting approval";
  fields.paymentStatus = selectedService.community ? "No payment required" : "Awaiting approval";
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

async function updateQuestionPayment(env, recordName, values, preserveAvailability = false) {
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
    if (preserveAvailability && ["Awaiting approval", "Payment requested", "Declined — no charge"].includes(status)) return { ok: true, paymentStatus: status };
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
  if (isPetAssist && record.visitStatus && !["accepted", "en-route", "in-progress", "completed"].includes(record.visitStatus)) return null;
  if (!isPetAssist && fieldValue(record, "paymentStatus") !== "Paid" && ["archived", "answered"].includes(fieldValue(record, "status"))) return null;
  const allowedAmounts = new Set(isPetAssist ? Object.values(PETASSIST_SERVICES).map(service => service.amount) : [10, 15, 25, 5, 20, 30, 35]);
  if (!["Payment requested", "Paid"].includes(fieldValue(record, "paymentStatus")) || !allowedAmounts.has(amount)) return null;
  return {
    amount: amount.toFixed(2),
    service: fieldValue(record, "requestedService") || "Paws & Whiskers Care Line service",
  };
}

async function serveCheckout(url, env) {
  const recordName = url.searchParams.get("question") || "";
  const record = await fetchQuestionFromCloudKit(env, recordName);
  const status = fieldValue(record, "paymentStatus");
  if (status === "Declined — no charge" || (status === "Awaiting approval" && ["archived", "answered"].includes(fieldValue(record, "status")))) {
    return checkoutMessage("Request not accepted", "The care line cannot take this question at this time. No payment was requested or charged for this request.", 200);
  }
  if (status === "Awaiting approval") return checkoutMessage("Waiting for approval", "Your question was received. The operator needs to confirm availability before you can pay. You have not been charged. Return to your private conversation to check for updates. For urgent concerns, contact a veterinarian instead of waiting.", 200, true);
  if (status === "No payment required") return checkoutMessage("No payment required", "Your Free Community Support request has been received. Check your private conversation for replies.", 200);
  const offer = record && paidOffer(record);
  if (!offer) return checkoutMessage("Payment link unavailable", "This payment request is no longer available. Please contact the care line.", 404);
  if (fieldValue(record, "paymentStatus") === "Paid") return paidCheckoutConfirmation(record);
  if (!env.PAYPAL_CLIENT_ID || !env.PAYPAL_CLIENT_SECRET) {
    return checkoutMessage("Checkout is being connected", "Please contact the care line for a payment link.", 503);
  }

  const safeQuestion = JSON.stringify(recordName).replace(/</g, "\\u003c");
  const safeAmount = JSON.stringify(offer.amount);
  const safeService = escapeHTML(offer.service);
  const visitsCheckout = recordName.startsWith("petassist-");
  const brand = visitsCheckout ? "Paws & Whiskers Visits" : "Paws & Whiskers Care Line";
  const pageStyle = visitsCheckout
    ? "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0e1014;color:#f7f8fa;margin:0}.card{max-width:520px;margin:32px auto;background:#191d24;border:1px solid #35383e;border-radius:18px;padding:24px}.brand{color:#f2c65b;font-weight:800}h1{font-size:1.6rem}a{color:#f2c65b}.amount{font-size:2rem;font-weight:800;margin:.35rem 0 1rem;color:#f2c65b}.note{color:#c9cdd5;line-height:1.45}#applepay-container{margin:14px 0}apple-pay-button{--apple-pay-button-width:100%;--apple-pay-button-height:48px;--apple-pay-button-border-radius:12px}#status{font-weight:650;margin-top:16px}"
    : "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f4f7fa;color:#132238;margin:0}.card{max-width:520px;margin:32px auto;background:white;border-radius:18px;padding:24px;box-shadow:0 10px 35px #13223818}.brand{color:#173f67}h1{font-size:1.6rem}.amount{font-size:2rem;font-weight:800;margin:.35rem 0 1rem}.note{color:#536579;line-height:1.45}#applepay-container{margin:14px 0}apple-pay-button{--apple-pay-button-width:100%;--apple-pay-button-height:48px;--apple-pay-button-border-radius:8px}#status{font-weight:650;margin-top:16px}";
  const sdkURL = `https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(env.PAYPAL_CLIENT_ID)}&currency=USD&components=buttons,applepay`;
  return new Response(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Secure payment</title><script src="${sdkURL}"></script><script src="https://applepay.cdn-apple.com/jsapi/1.latest/apple-pay-sdk.js"></script>
<style>${pageStyle}</style></head><body><main class="card"><div class="brand">${brand}</div><h1 id="checkout-title">${safeService}</h1><div class="amount">$${offer.amount}</div><p id="checkout-note" class="note">Choose PayPal or Apple Pay. Payment status updates automatically after payment succeeds.</p><div id="checkout-controls"><div id="paypal-buttons"></div><div id="applepay-container"></div><p id="applepay-status" class="note" role="status"></p></div><p id="status" role="status" tabindex="-1"></p>${checkoutNextAction(recordName, true)}</main>
<script>const question=${safeQuestion}, amount=${safeAmount}, brand=${JSON.stringify(brand)};
const statusEl=document.getElementById('status');
const appleStatus=document.getElementById('applepay-status');
let paymentComplete=false;
function finishCheckout(d){
  paymentComplete=true;
  document.getElementById('checkout-controls').hidden=true;
  document.getElementById('paypal-buttons').innerHTML='';
  document.getElementById('applepay-container').innerHTML='';
  document.getElementById('checkout-title').textContent=d.status==='Paid'?'Payment received':'Payment status updated';
  document.getElementById('checkout-note').textContent=question.startsWith('petassist-')?'Your visit payment is complete. Return to your private visit page for appointment updates.':'Your question and payment have been received. Your reply will arrive through the method you selected.';
  document.getElementById('checkout-next').hidden=false;
  statusEl.focus();
}
async function createOrder(){if(paymentComplete)throw new Error('This request is already paid');const r=await fetch('/api/paypal/orders',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question})});const d=await r.json();if(!r.ok||!d.id)throw new Error(d.error||'Could not start payment');return d.id}
async function capture(orderID,method){const r=await fetch('/api/paypal/orders/'+encodeURIComponent(orderID)+'/capture',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({question,method})});const d=await r.json();if(!r.ok)throw new Error(d.error||'Could not complete payment');statusEl.textContent=d.status==='Paid'?(d.statusSyncPending?'Payment received. Your care-line payment status is updating. Thank you!':'Payment received. Thank you!'):'Payment status: '+d.status+'. Please contact the care line with any questions.';finishCheckout(d);return d}
if(window.paypal && paypal.Buttons){paypal.Buttons({createOrder,onApprove:d=>capture(d.orderID,'PayPal'),onCancel:()=>{if(paymentComplete)return;statusEl.textContent='Payment cancelled. You can try again when ready.'},onError:()=>{if(paymentComplete)return;statusEl.textContent='Payment could not be confirmed. If you approved a payment, contact the care line before trying again.'}}).render('#paypal-buttons').catch(()=>{statusEl.textContent='Checkout could not load. Please reload this page or contact the care line.'})}else{statusEl.textContent='Checkout could not load. Please reload this page or contact the care line.'}
async function setupApplePay(){
  if(paymentComplete)return;
  try {
    if(!window.paypal||!paypal.Applepay||!window.ApplePaySession||!ApplePaySession.canMakePayments()){
      appleStatus.textContent='Apple Pay is unavailable in this browser. You can use PayPal or the card option above.';return;
    }
    const applepay=paypal.Applepay();const c=await applepay.config();
    if(paymentComplete)return;
    if(!c.isEligible){appleStatus.textContent='Apple Pay is currently unavailable. You can use PayPal or the card option above.';return;}
    document.getElementById('applepay-container').innerHTML='<apple-pay-button id="applepay-button" buttonstyle="black" type="pay" locale="en-US"></apple-pay-button>';
    appleStatus.textContent='';
    let active=false;
    document.getElementById('applepay-button').onclick=()=>{
      if(active||paymentComplete)return;
      let session;
      try {
        session=new ApplePaySession(4,{countryCode:c.countryCode,merchantCapabilities:c.merchantCapabilities,supportedNetworks:c.supportedNetworks,currencyCode:'USD',requiredBillingContactFields:['postalAddress'],total:{label:brand,type:'final',amount}});
        active=true;appleStatus.textContent='';
        session.onvalidatemerchant=async e=>{
          try{const v=await applepay.validateMerchant({validationUrl:e.validationURL,displayName:brand});session.completeMerchantValidation(v.merchantSession);}
          catch{active=false;appleStatus.textContent='Apple Pay could not verify this checkout. Please use PayPal or the card option, or contact the care line.';session.abort();}
        };
        session.onpaymentauthorized=async e=>{
          let confirmed=false;
          try{const id=await createOrder();await applepay.confirmOrder({orderId:id,token:e.payment.token,billingContact:e.payment.billingContact});confirmed=true;await capture(id,'Apple Pay');session.completePayment(ApplePaySession.STATUS_SUCCESS);appleStatus.textContent='';}
          catch{session.completePayment(ApplePaySession.STATUS_FAILURE);appleStatus.textContent=confirmed?'Apple Pay payment could not be confirmed. If your wallet shows a charge, contact the care line before trying again.':'Apple Pay could not complete payment. Please try another card or use PayPal.';}
          finally{active=false;}
        };
        session.oncancel=()=>{active=false;if(paymentComplete)return;appleStatus.textContent='Apple Pay cancelled. You can try again when ready.';};
        session.begin();
      }catch{active=false;appleStatus.textContent='Apple Pay could not open. Please use PayPal or the card option, or contact the care line.';}
    };
  }catch{appleStatus.textContent='Apple Pay could not load. Please reload or use PayPal or the card option.';}
}
setupApplePay();
</script></body></html>`, { headers: securityHTMLHeaders() });
}

function checkoutNextAction(recordName, hidden = false) {
  const isPetAssist = recordName.startsWith("petassist-");
  const href = isPetAssist ? "https://bayareaapps.com/petassist-local/" : "https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/#askSection";
  const label = isPetAssist ? "Return to Paws & Whiskers Visits" : "Ask another question";
  const color = isPetAssist ? "#c81e30" : "#173f67";
  return `<p id="checkout-next"${hidden ? " hidden" : ""}><a href="${href}" style="display:inline-block;background:${color};color:white;padding:14px 20px;border-radius:12px;text-decoration:none;font-weight:700">${label}</a></p>`;
}

function paidCheckoutConfirmation(record) {
  const isPetAssist = record.recordName.startsWith("petassist-");
  const next = isPetAssist ? "Keep your private visit link for appointment updates and messages. Contact info@bayareaapps.com if you need help." : "Your reply will arrive through the method you selected. To submit a new question, use the button below.";
  const style = isPetAssist
    ? "body{font-family:-apple-system,sans-serif;max-width:540px;margin:48px auto;padding:20px;background:#0e1014;color:#f7f8fa;line-height:1.6}h1{color:#f2c65b}a{color:#f2c65b}"
    : "body{font-family:-apple-system,sans-serif;max-width:540px;margin:48px auto;padding:20px;color:#132238;line-height:1.6}h1{color:#173f67}";
  return new Response(`<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><title>Payment received</title><style>${style}</style></head><body><main><h1>Payment received</h1><p>This request is already paid. Thank you!</p><p>${next}</p>${checkoutNextAction(record.recordName)}</main></body></html>`, { headers: securityHTMLHeaders() });
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
  // The verified capture is the payment outcome. Webhooks retry status syncing;
  // a delayed CloudKit write must not tell the payer that their charge failed.
  let update;
  try { update = await updateQuestionPayment(env, recordName, { paymentStatus: "Paid", paymentMethod: method }); } catch {}
  if (!update?.ok) return json({ ok: true, status: "Paid", statusSyncPending: true }, 202);
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

function checkoutMessage(title, message, status, refresh = false) {
  return new Response(`<!doctype html><meta name="viewport" content="width=device-width"><title>${escapeHTML(title)}</title><style>body{font-family:-apple-system,sans-serif;max-width:540px;margin:48px auto;padding:20px;color:#132238}h1{color:#173f67}</style><h1>${escapeHTML(title)}</h1><p>${escapeHTML(message)}</p>${refresh ? '<button type="button" onclick="location.reload()">Check again</button>' : ""}`, { status, headers: securityHTMLHeaders() });
}

function securityHTMLHeaders() {
  return { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer", "Content-Security-Policy": "default-src 'self'; script-src 'self' 'unsafe-inline' https://*.paypal.com https://*.paypalobjects.com https://applepay.cdn-apple.com; frame-src 'self' https://*.paypal.com https://applepay.cdn-apple.com; connect-src 'self' https://*.paypal.com https://*.paypalobjects.com; style-src 'self' 'unsafe-inline' https://*.paypal.com https://*.paypalobjects.com; img-src 'self' data: https://*.paypal.com https://*.paypalobjects.com https://applepay.cdn-apple.com" };
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
  const cors = { ...corsHeaders(request, env), "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS", "Access-Control-Allow-Headers": "Content-Type, Authorization", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" };
  if (request.headers.has("Origin") && !isAllowedOrigin(request, env)) return json({ error: "Origin not allowed" }, 403, cors);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (!env.PETASSIST_PAYMENTS) return json({ error: "PetAssist payments are being connected" }, 503, cors);
  if (url.pathname === "/petassist/device-connection" && request.method === "POST") return ownerDeviceConnection(request, env, cors);
  if (url.pathname.startsWith("/petassist/operator/") || url.pathname.startsWith("/petassist/client/") || url.pathname === "/petassist/requests" || url.pathname === "/petassist/service-area") return handleVisits(request, env, url, cors);
  if (request.method === "POST" && url.pathname === "/petassist/bookings") {
    if (!await secretMatches((request.headers.get("Authorization") || "").replace(/^Bearer /, ""), env.PETASSIST_OPERATOR_KEY)) return json({ error: "Use the website visit request form. The business confirms visits before requesting payment." }, 401, cors);
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
    if (record.visitStatus === "cancelled") return checkoutMessage("Visit cancelled", "This appointment has been cancelled. Contact info@bayareaapps.com about any payment or refund questions.", 200);
    if (record.visitStatus === "requested") return checkoutMessage("Awaiting appointment confirmation", "We will confirm availability before requesting payment. Use your private visit page for updates.", 200);
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
    if (path === "/thread") return Response.json(await this.state.storage.get("care-thread") || null);
    if(path.startsWith("/thread-")) {
      const input=await request.json();
      return this.state.storage.transaction(async txn=>{
        let thread=await txn.get("care-thread");
        if(path==="/thread-init") {
          if(thread && (thread.deleted || thread.clientAccess!==input.clientAccess))return Response.json({error:"Conflict"},{status:409});
          if(!thread){thread={clientAccess:input.clientAccess,messages:[]};await txn.put("care-thread",thread);}
          return Response.json({ok:true});
        }
        if(!thread || thread.deleted)return Response.json({error:"Conversation unavailable"},{status:404});
        if(path==="/thread-bind") {
          if(thread.recordName && thread.recordName!==input.recordName)return Response.json({error:"Conflict"},{status:409});
          thread.recordName=input.recordName;
        } else if(path==="/thread-delete") {thread={deleted:true};}
        else if(path==="/thread-message") {
          if(input.sender==="client" && input.clientAccess!==thread.clientAccess)return Response.json({error:"Unauthorized"},{status:401});
          const previous=thread.messages.find(message=>message.id===input.id);
          if(previous && (previous.sender!==input.sender || previous.text!==input.text))return Response.json({error:"Message reference already used. Refresh and retry."},{status:409});
          if(!previous) {
            if(thread.messages.length>=1000)return Response.json({error:"This conversation is full. Contact info@bayareaapps.com."},{status:409});
            thread.messages.push({id:input.id,sender:input.sender,text:input.text,createdAt:new Date().toISOString()});
          }
        } else return Response.json({error:"Not found"},{status:404});
        await txn.put("care-thread",thread);return Response.json({ok:true});
      });
    }
    if (path === "/service-area") return Response.json(await this.state.storage.get("service-area") || null);
    if (path === "/record") return Response.json(await this.state.storage.get("record") || null);
    if (path === "/index") {
      const query = new URL(request.url).searchParams;
      const entries = await this.state.storage.list({prefix:"visit:", limit:101, ...(query.get("cursor") ? {startAfter:query.get("cursor")} : {})});
      const keys = [...entries.keys()];
      return Response.json({tokens:keys.slice(0,100).map(key=>key.slice(6)), cursor:keys.length>100?keys[99]:null});
    }
    const input = await request.json();
    return this.state.storage.transaction(async txn => {
      let record = await txn.get("record");
      if (path === "/device-proof") {
        const used = await txn.get("device-nonces") || [];
        if (used.some(item => item.nonce === input.nonce)) return Response.json({ok:false},{status:409});
        const active = used.filter(item => item.timestamp >= Date.now() - 120000);
        if (active.length >= 100) return Response.json({ok:false},{status:429});
        active.push({nonce:input.nonce,timestamp:Date.now()}); await txn.put("device-nonces",active);
        return Response.json({ok:true});
      }
      if (path === "/service-area-save") { await txn.put("service-area",input); return Response.json(input); }
      if (path === "/index-add") { await txn.put("visit:"+input.token,true); return Response.json({ok:true}); }
      if (path === "/visit-create") {
        if (record) return Response.json(record, {status:record.clientAccess===input.clientAccess?200:409});
        const fields = Object.fromEntries(Object.entries({requestedService:input.serviceTitle,paymentAmount:"$"+input.amount,paymentStatus:"Payment requested",paymentMethod:"PayPal or Apple Pay",sourceChannel:"Paws & Whiskers Visits"}).map(([key,value])=>[key,{value}]));
        record={recordName:"petassist-"+input.token,recordType:"PetAssistPayment",recordChangeTag:"1",serviceID:input.service,fields,visitStatus:"requested",createdAt:new Date().toISOString(),clientAccess:input.clientAccess,details:input.details,messages:[]};
        await txn.put("record",record); return Response.json(record);
      }
      if (path === "/redact") {
        if (!record?.details) return Response.json({error:"Visit not found"},{status:404});
        if (input.expectedVersion !== record.recordChangeTag) return Response.json({error:"This visit changed. Refresh before removing client details."},{status:409});
        delete record.details; delete record.clientAccess; record.messages=[]; record.visitStatus="cancelled";
        record.recordChangeTag=String(Number(record.recordChangeTag)+1);
        await txn.put("record",record); return Response.json({ok:true});
      }
      if (path === "/visit-update" || path === "/message" || path === "/location") {
        if (!record?.details) return Response.json({error:"Visit not found"},{status:404});
        if (path === "/location") {
          if (input.expectedVersion !== record.recordChangeTag) return Response.json({error:"This visit changed. Refresh before saving its location."},{status:409});
          if (input.location) record.details.location=input.location; else delete record.details.location;
        } else if (path === "/message") {
          if (record.messages.length >= 500) return Response.json({error:"This conversation is full. Contact info@bayareaapps.com."},{status:409});
          record.messages.push({id:crypto.randomUUID(),sender:input.sender,text:input.text,createdAt:new Date().toISOString()});
        } else {
          if (input.expectedVersion !== record.recordChangeTag) return Response.json({error:"This visit changed. Refresh before saving."},{status:409});
          const next=input.status;
          const transitions={requested:["accepted","cancelled"],accepted:["accepted","en-route","cancelled"],"en-route":["in-progress","cancelled"],"in-progress":["completed","cancelled"],completed:[],cancelled:[]};
          if (!transitions[record.visitStatus]?.includes(next)) return Response.json({error:"Invalid appointment change"},{status:409});
          if (input.scheduledAt) record.details.scheduledAt=input.scheduledAt;
          if (next==="accepted" && !record.details.scheduledAt) return Response.json({error:"Choose an appointment time"},{status:400});
          record.visitStatus=next;
          if(next==="completed") record.completedAt=new Date().toISOString();
        }
        record.recordChangeTag=String(Number(record.recordChangeTag)+1);
        await txn.put("record",record);return Response.json(record);
      }
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


async function secretMatches(provided, expected) {
  if (!provided || !expected) return false;
  const digest = value => crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  const [a,b] = await Promise.all([digest(provided),digest(expected)]);
  const left=new Uint8Array(a),right=new Uint8Array(b);let diff=0;
  for(let i=0;i<left.length;i++)diff|=left[i]^right[i];
  return diff===0;
}
function visitsIndex(env) { return env.PETASSIST_PAYMENTS.get(env.PETASSIST_PAYMENTS.idFromName("private-visits-index")); }
function validVisitLocation(value) {
  return value && typeof value.latitude === "number" && typeof value.longitude === "number" && Number.isFinite(value.latitude) && Number.isFinite(value.longitude) && Math.abs(value.latitude)<=90 && Math.abs(value.longitude)<=180;
}
function distanceMiles(a,b) {
  if(!validVisitLocation(a) || !validVisitLocation(b))return null;
  const rad=value=>value*Math.PI/180;
  const h=Math.sin(rad(b.latitude-a.latitude)/2)**2+Math.cos(rad(a.latitude))*Math.cos(rad(b.latitude))*Math.sin(rad(b.longitude-a.longitude)/2)**2;
  return Math.round(3958.7613*2*Math.asin(Math.sqrt(Math.min(1,Math.max(0,h))))*10)/10;
}
function visitSummary(record, requestURL, operator=false, serviceArea=null) {
  const receipt=petAssistReceipt(record,requestURL);
  const summary={...receipt,serviceID:record.serviceID,visitStatus:record.visitStatus,version:record.recordChangeTag,createdAt:record.createdAt,preferredAt:record.details.preferredAt,scheduledAt:record.details.scheduledAt||null,petName:record.details.petName,address:record.details.address,location:record.details.location||null,messages:record.messages||[]};
  if(operator)Object.assign(summary,record.details,{serviceArea,distanceMiles:distanceMiles(serviceArea,record.details.location),clientLink:"https://bayareaapps.com/petassist-local/#visit="+receipt.token+"."+record.clientAccess});
  return summary;
}
async function limitedVisitJSON(request) {
  const text=await request.text();
  if(new TextEncoder().encode(text).length>16000)return null;
  try{const value=JSON.parse(text);return value && typeof value === "object" && !Array.isArray(value)?value:null;}catch{return null;}
}
async function handleVisits(request,env,url,cors) {
  const isOperator=url.pathname.startsWith("/petassist/operator/");
  const bearer=(request.headers.get("Authorization")||"").replace(/^Bearer /,"");
  if(isOperator && !await secretMatches(bearer,env.PETASSIST_OPERATOR_KEY))return json({error:"Connect your business app to access visits."},401,cors);
  const serviceArea=await (await visitsIndex(env).fetch("https://booking.invalid/service-area")).json();
  if(url.pathname==="/petassist/service-area" && request.method==="GET")return json(await secretMatches(bearer,env.PETASSIST_OPERATOR_KEY)?serviceArea:null,200,cors);
  if(url.pathname==="/petassist/operator/service-area" && request.method==="PATCH") {
    const input=await limitedVisitJSON(request);
    if(!validVisitLocation(input) || typeof input.label!=="string" || !input.label.trim() || input.label.length>200 || /[\u0000-\u001f]/.test(input.label))return json({error:"Choose a public business city, ZIP code, or address."},400,cors);
    const area={label:input.label.trim(),latitude:input.latitude,longitude:input.longitude};
    const saved=await visitsIndex(env).fetch("https://booking.invalid/service-area-save",{method:"POST",body:JSON.stringify(area)});
    return json(await saved.json(),200,cors);
  }
  if(url.pathname==="/petassist/operator/visits" && request.method==="GET") {
    const cursor=url.searchParams.get("cursor")||"";
    if(cursor && !/^visit:[a-f0-9]{32}$/.test(cursor))return json({error:"Invalid page"},400,cors);
    const page=await (await visitsIndex(env).fetch("https://booking.invalid/index?cursor="+encodeURIComponent(cursor))).json();
    const records=await Promise.all(page.tokens.map(token=>readPetAssistPayment(env,"petassist-"+token)));
    return json({visits:records.filter(record=>record?.details).map(record=>visitSummary(record,request.url,true,serviceArea)),cursor:page.cursor},200,cors);
  }
  if(url.pathname==="/petassist/requests" && request.method==="POST") {
    if(!(await allowIntakeRequest(request,env)))return json({error:"Please wait a minute before trying again."},429,cors);
    const input=await limitedVisitJSON(request);
    if(input?.website)return json({ok:true},200,cors);
    const service=Object.hasOwn(PETASSIST_SERVICES,input?.service||"")?PETASSIST_SERVICES[input.service]:null;
    if(!service || !/^[a-f0-9]{32}$/.test(input?.token||"") || !/^[a-f0-9]{64}$/.test(input?.clientAccess||"") || input.acceptedPrivacy!==true)return json({error:"Check your service selection and accept the privacy notice."},400,cors);
    const limits={clientName:100,email:200,phone:40,petName:100,species:60,address:500,notes:2000};const details={};
    for(const [key,max] of Object.entries(limits)) {
      const value=typeof input[key]==="string"?input[key].trim():"";
      if(value.length>max || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(value))return json({error:"Please shorten the "+key+" field."},400,cors);
      details[key]=value;
    }
    if(!details.clientName || !details.petName || !details.address || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(details.email))return json({error:"Enter your name, email, pet name and visit address."},400,cors);
    const date=new Date(input.preferredAt);if(!Number.isFinite(date.getTime()) || date.getTime()<Date.now() || date.getTime()>Date.now()+366*86400000)return json({error:"Choose a preferred visit time within the next year."},400,cors);
    details.preferredAt=date.toISOString();
    if(input.location!=null) {
      if(!validVisitLocation(input.location) || input.locationConfirmed!==true)return json({error:"Confirm that the shared location is your visit address."},400,cors);
      details.location={latitude:input.location.latitude,longitude:input.location.longitude,source:"client-shared"};
    }
    const object=petAssistObject(env,"petassist-"+input.token);
    const created=await object.fetch("https://booking.invalid/visit-create",{method:"POST",body:JSON.stringify({...input,details,serviceTitle:service.title,amount:service.amount})});
    if(!created.ok)return json({error:"This request reference is already in use. Reload the form."},409,cors);
    const indexed=await visitsIndex(env).fetch("https://booking.invalid/index-add",{method:"POST",body:JSON.stringify({token:input.token})});
    if(!indexed.ok)return json({error:"The request could not be delivered. Please retry."},503,cors);
    return json({ok:true,token:input.token,clientLink:"https://bayareaapps.com/petassist-local/#visit="+input.token+"."+input.clientAccess},200,cors);
  }
  const match=url.pathname.match(/^\/petassist\/(operator|client)\/visits\/([a-f0-9]{32})(?:\/(messages|location))?$/);
  if(!match)return json({error:"Not found"},404,cors);
  const object=petAssistObject(env,"petassist-"+match[2]);
  const record=await readPetAssistPayment(env,"petassist-"+match[2]);
  if(!record?.details)return json({error:"Visit not found"},404,cors);
  if(!isOperator && !await secretMatches(bearer,record.clientAccess))return json({error:"Open your private visit link to access this page."},401,cors);
  if(request.method==="GET" && !match[3])return json(visitSummary(record,request.url,isOperator,serviceArea),200,cors);
  if(isOperator && request.method==="DELETE" && !match[3]) {
    const input=await limitedVisitJSON(request);
    if(typeof input?.expectedVersion!=="string")return json({error:"Refresh this visit before removing client details."},400,cors);
    const result=await object.fetch("https://booking.invalid/redact",{method:"POST",body:JSON.stringify({expectedVersion:input.expectedVersion})});
    return json(await result.json(),result.status,cors);
  }
  if(request.method==="PATCH" && match[3]==="location") {
    if(!isOperator && !(await allowIntakeRequest(request,env)))return json({error:"Please wait before updating your location."},429,cors);
    const input=await limitedVisitJSON(request);
    if(typeof input?.expectedVersion!=="string" || (input.location!=null && (!validVisitLocation(input.location) || (!isOperator && input.locationConfirmed!==true))))return json({error:"Confirm the visit location and refresh before saving."},400,cors);
    const location=input.location ? {latitude:input.location.latitude,longitude:input.location.longitude,source:isOperator?"visit-address":"client-shared"}:null;
    const result=await object.fetch("https://booking.invalid/location",{method:"POST",body:JSON.stringify({location,expectedVersion:input.expectedVersion})});
    if(!result.ok)return json(await result.json(),result.status,cors);
    return json(visitSummary(await result.json(),request.url,isOperator,serviceArea),200,cors);
  }
  if(request.method==="POST" && match[3]==="messages") {
    if(!isOperator && !(await allowIntakeRequest(request,env)))return json({error:"Please wait before sending another message."},429,cors);
    const input=await limitedVisitJSON(request);const text=typeof input?.text==="string"?input.text.trim():"";
    if(!text || text.length>2000)return json({error:"Enter a message of up to 2,000 characters."},400,cors);
    const result=await object.fetch("https://booking.invalid/message",{method:"POST",body:JSON.stringify({text,sender:isOperator?"business":"client"})});
    if(!result.ok)return json(await result.json(),result.status,cors);
    return json(visitSummary(await result.json(),request.url,isOperator,serviceArea),200,cors);
  }
  if(isOperator && request.method==="PATCH" && !match[3]) {
    const input=await limitedVisitJSON(request);
    if(!input || typeof input.expectedVersion!=="string")return json({error:"Refresh this visit before saving."},400,cors);
    if(input.scheduledAt && (!Number.isFinite(new Date(input.scheduledAt).getTime()) || new Date(input.scheduledAt).getTime()<Date.now()))return json({error:"Choose a future appointment time."},400,cors);
    const result=await object.fetch("https://booking.invalid/visit-update",{method:"POST",body:JSON.stringify({status:input.status,scheduledAt:input.scheduledAt,expectedVersion:input.expectedVersion})});
    if(!result.ok)return json(await result.json(),result.status,cors);
    return json(visitSummary(await result.json(),request.url,true,serviceArea),200,cors);
  }
  return json({error:"Method not allowed"},405,cors);
}

async function ownerDeviceConnection(request, env, cors) {
  const rejected = () => json({error:"This iPhone is not authorized for business access."},401,cors);
  if (!env.PETASSIST_DEVICE_PUBLIC_KEY || !env.PETASSIST_OPERATOR_KEY) return rejected();
  const input = await limitedVisitJSON(request);
  if (!input || typeof input.publicKey !== "string" || !await secretMatches(input.publicKey,env.PETASSIST_DEVICE_PUBLIC_KEY.trim()) || !/^[a-f0-9]{32}$/.test(input.nonce || "") || !/^\d{10}$/.test(input.timestamp || "") || Math.abs(Date.now()-Number(input.timestamp)*1000)>60000) return rejected();
  try {
    const decode = text => Uint8Array.from(atob(text),char=>char.charCodeAt(0));
    const signature = decode(input.signature || ""); if(signature.length !== 64)return rejected();
    const key = await crypto.subtle.importKey("raw",decode(input.publicKey),{name:"ECDSA",namedCurve:"P-256"},false,["verify"]);
    const payload = new TextEncoder().encode("PawsVisitsDevice/v1\n"+input.publicKey+"\n"+input.nonce+"\n"+input.timestamp);
    if(!await crypto.subtle.verify({name:"ECDSA",hash:"SHA-256"},key,signature,payload))return rejected();
    const proof = await visitsIndex(env).fetch("https://booking.invalid/device-proof",{method:"POST",body:JSON.stringify({nonce:input.nonce})});
    if(!proof.ok)return rejected();
    return json({connectionKey:env.PETASSIST_OPERATOR_KEY},200,{...cors,"Cache-Control":"no-store"});
  } catch { return rejected(); }
}

function careObject(env,token) {return env.PETASSIST_PAYMENTS.get(env.PETASSIST_PAYMENTS.idFromName("careline-thread-"+token));}
async function careIntakeReceipt(recordName,token,access,url,env,cors) {
  const record=await fetchQuestionFromCloudKit(env,recordName);
  if(!record)return json({error:"Your question could not be confirmed. Retry with the same form."},503,cors);
  const checkoutURL=fieldValue(record,"paymentStatus")==="Payment requested" && paidOffer(record)?url.origin+"/pay?question="+encodeURIComponent(recordName):"";
  return json({ok:true,recordName,checkoutURL,conversationURL:"https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/conversation.html#thread="+token+"."+access},200,cors);
}
async function careDeviceConnection(request,env,cors) {
  const rejected=()=>json({error:"This iPhone is not authorized for Care Line replies."},401,cors);
  if(!env.CARELINE_DEVICE_PUBLIC_KEY || !env.CARELINE_OPERATOR_KEY)return rejected();
  const input=await limitedVisitJSON(request);
  if(!input || input.publicKey!==env.CARELINE_DEVICE_PUBLIC_KEY.trim() || !/^[a-f0-9]{32}$/.test(input.nonce||"") || !/^\d{10}$/.test(input.timestamp||"") || Math.abs(Date.now()-Number(input.timestamp)*1000)>60000)return rejected();
  try {
    const decode=text=>Uint8Array.from(atob(text),char=>char.charCodeAt(0));
    const signature=decode(input.signature||"");if(signature.length!==64)return rejected();
    const key=await crypto.subtle.importKey("raw",decode(input.publicKey),{name:"ECDSA",namedCurve:"P-256"},false,["verify"]);
    const payload=new TextEncoder().encode("PawsCareLineDevice/v1\n"+input.publicKey+"\n"+input.nonce+"\n"+input.timestamp);
    if(!await crypto.subtle.verify({name:"ECDSA",hash:"SHA-256"},key,signature,payload))return rejected();
    const nonce=await visitsIndex(env).fetch("https://care.invalid/device-proof",{method:"POST",body:JSON.stringify({nonce:input.nonce})});
    if(!nonce.ok)return rejected();
    return json({connectionKey:env.CARELINE_OPERATOR_KEY},200,cors);
  } catch{return rejected();}
}
async function handleCareline(request,env,url) {
  const cors={...corsHeaders(request,env),"Access-Control-Allow-Methods":"GET, POST, DELETE, OPTIONS","Access-Control-Allow-Headers":"Content-Type, Authorization","Cache-Control":"private, no-store","Referrer-Policy":"no-referrer"};
  if(request.headers.has("Origin") && !isAllowedOrigin(request,env))return json({error:"Origin not allowed"},403,cors);
  if(request.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
  if(!env.PETASSIST_PAYMENTS)return json({error:"Conversations are unavailable."},503,cors);
  if(url.pathname==="/careline/device-connection" && request.method==="POST")return careDeviceConnection(request,env,cors);
  if(url.pathname==="/careline/operator/status" && request.method==="GET") {
    const bearer=(request.headers.get("Authorization")||"").replace(/^Bearer /,"");
    return await secretMatches(bearer,env.CARELINE_OPERATOR_KEY)?json({ok:true},200,cors):json({error:"Unauthorized"},401,cors);
  }
  const legacy=url.pathname.match(/^\/careline\/operator\/questions\/([A-Za-z0-9_.:-]{1,255})\/conversation$/);
  if(legacy && request.method==="POST") {
    const bearer=(request.headers.get("Authorization")||"").replace(/^Bearer /,"");
    if(!await secretMatches(bearer,env.CARELINE_OPERATOR_KEY))return json({error:"Unauthorized"},401,cors);
    for(let attempt=0;attempt<3;attempt++) {
      const record=await fetchQuestionFromCloudKit(env,legacy[1]);
      if(!record || record.recordType!=="Question" || legacy[1].startsWith("petassist-"))return json({error:"Question unavailable"},404,cors);
      const envelope=intakeEnvelope(fieldValue(record,"question"))||{format:"paws-intake-v1",question:fieldValue(record,"question"),details:{}};
      let token=envelope.details.conversationToken;
      if(!/^[a-f0-9]{32}$/.test(token||"")) {
        token=crypto.randomUUID().replaceAll("-","");
        const access=crypto.randomUUID().replaceAll("-","")+crypto.randomUUID().replaceAll("-","");
        const object=careObject(env,token);
        await object.fetch("https://care.invalid/thread-init",{method:"POST",body:JSON.stringify({clientAccess:access})});
        await object.fetch("https://care.invalid/thread-bind",{method:"POST",body:JSON.stringify({recordName:record.recordName})});
        envelope.details.conversationToken=token;
        const saved=await saveQuestionToCloudKit(env,JSON.stringify({operations:[{operationType:"update",record:{recordType:"Question",recordName:record.recordName,recordChangeTag:record.recordChangeTag,fields:{question:{value:JSON.stringify(envelope)}}}}]}));
        if(!saved.ok) {
          await object.fetch("https://care.invalid/thread-delete",{method:"POST",body:"{}"});
          if(saved.conflict)continue;
          return json({error:"The conversation could not be created. Retry."},503,cors);
        }
      }
      const next=new URL(request.url);next.pathname="/careline/operator/threads/"+token;
      return handleCareline(new Request(next,{headers:request.headers}),env,next);
    }
    return json({error:"Question changed. Refresh and retry."},409,cors);
  }
  const match=url.pathname.match(/^\/careline\/(operator|client)\/threads\/([a-f0-9]{32})(?:\/(messages))?$/);
  if(!match)return json({error:"Not found"},404,cors);
  const operator=match[1]==="operator",bearer=(request.headers.get("Authorization")||"").replace(/^Bearer /,"");
  if(operator && !await secretMatches(bearer,env.CARELINE_OPERATOR_KEY))return json({error:"Open Care Line on your authorized iPhone."},401,cors);
  const object=careObject(env,match[2]),thread=await (await object.fetch("https://care.invalid/thread")).json();
  if(!operator && !await secretMatches(bearer,thread?.clientAccess))return json({error:"This private conversation link is invalid."},401,cors);
  if(operator && request.method==="DELETE" && !match[3] && thread?.deleted)return json({ok:true},200,cors);
  if(!thread?.recordName || thread.deleted)return json({error:"This conversation is no longer available."},404,cors);
  const record=await fetchQuestionFromCloudKit(env,thread.recordName);
  if(!record)return json({error:"This conversation is no longer available."},404,cors);
  if(operator && request.method==="DELETE" && !match[3]) {
    const result=await object.fetch("https://care.invalid/thread-delete",{method:"POST",body:"{}"});return json(await result.json(),result.status,cors);
  }
  if(request.method==="POST" && match[3]==="messages") {
    const input=await limitedVisitJSON(request),text=typeof input?.text==="string"?input.text.trim():"";
    if(!text || text.length>4000 || !/^[a-f0-9]{32}$/.test(input?.id||""))return json({error:"Enter a message of 1–4,000 characters."},400,cors);
    if(!operator && moderateClientMessage(text).blocked)return json({error:"Please revise this message to follow our communication policy."},400,cors);
    const result=await object.fetch("https://care.invalid/thread-message",{method:"POST",body:JSON.stringify({id:input.id,text,sender:operator?"business":"client",clientAccess:operator?undefined:bearer})});
    if(!result.ok)return json(await result.json(),result.status,cors);
    // Delivery is already durable. A CloudKit badge failure must not invite a duplicate reply.
    try {await updateQuestionPayment(env,thread.recordName,{conversationStatus:operator?"Reply sent":"Needs response",status:operator?"answered":"new"},true);}catch{console.error("Conversation badge update unavailable");}
  } else if(request.method!=="GET" || match[3])return json({error:"Method not allowed"},405,cors);
  const fresh=await (await object.fetch("https://care.invalid/thread")).json();
  if(fresh.deleted)return json({error:"Conversation unavailable"},404,cors);
  const packed=intakeEnvelope(fieldValue(record,"question"));
  return json({token:match[2],petName:fieldValue(record,"petName"),question:packed?.question||fieldValue(record,"question"),service:fieldValue(record,"requestedService"),paymentStatus:fieldValue(record,"paymentStatus"),checkoutURL:fieldValue(record,"paymentStatus")==="Payment requested" && paidOffer(record)?url.origin+"/pay?question="+encodeURIComponent(thread.recordName):"",messages:fresh.messages,conversationURL:operator?"https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/conversation.html#thread="+match[2]+"."+fresh.clientAccess:undefined},200,cors);
}
