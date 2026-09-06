"use strict";
const byId = id => document.getElementById(id);
let catalog, selected, pending;
function showError(message) { byId("error").textContent = message; if (message) byId("error").focus(); }
function element(tag, text, className) {
  const node = document.createElement(tag); node.textContent = text;
  if (className) node.className = className;
  return node;
}
async function api(path, payload, token) {
  const response = await fetch(path, {method: payload ? "POST" : "GET", cache: "no-store", credentials: "omit",
    headers: {"Content-Type":"application/json", ...(token ? {"X-Question-Token":token} : {})},
    body: payload ? JSON.stringify(payload) : undefined});
  const body = await response.json();
  if (!response.ok) { const error=new Error(body.error || "Service unavailable."); error.status=response.status; throw error; }
  return body;
}
function selectCategory(category) {
  selected = category; byId("topic-guidance").hidden = false;
  for (const [id,key] of [["category-title","title"],["category-summary","summary"],["question-label","prompt"],["context-label","contextPrompt"],["excluded","notIncluded"]]) byId(id).textContent = category[key];
  byId("question").value = ""; byId("context").value = ""; byId("examples").replaceChildren();
  for (const example of category.examples) {
    const button = element("button", example, "example-button"); button.type = "button";
    button.addEventListener("click", () => { byId("question").value = example; byId("question").focus(); });
    byId("examples").append(button);
  }
}
function showPending(order) {
  pending = order; byId("intake-fields").disabled = true; byId("checkout-ready").hidden = false;
  byId("receipt-link").href = `status.html#${order.id}/${order.token}`;
  byId("order-summary").textContent = `${new Intl.NumberFormat("en-US", {style:"currency", currency:catalog.currency}).format(catalog.priceCents/100)} for one question. Check payment confirmation on your private question page.`;
}
byId("question-form").addEventListener("submit", async event => {
  event.preventDefault(); showError("");
  if (!selected) { showError("Choose one topic first."); return; }
  const button = byId("prepare"); button.disabled = true;
  const id = crypto.randomUUID();
  const token = Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2,"0")).join("");
  const payload = Object.fromEntries(new FormData(event.target));
  const confirmations = Object.fromEntries(catalog.screening.map(item => [item.id, byId(`confirm-${item.id}`).checked]));
  const order = {id, token, created:Date.now()};
  try {
    // Save only a recovery capability in this tab, never question text.
    try { sessionStorage.setItem("helpline-pending",JSON.stringify(order)); } catch { /* The visible private link remains available. */ }
    await api("api/questions", {...payload,id,token,category:selected.id,catalogVersion:catalog.version,confirmations});
    showPending(order); byId("receipt-link").focus();
  } catch (failure) {
    if (failure.status && failure.status < 500) {
      try {sessionStorage.removeItem("helpline-pending");}catch { /* Optional storage. */ }
      showError(failure.message);
    } else {
      showPending(order);
      showError(`${failure.message} Your private link is preserved. Open it before trying another submission.`);
    }
  } finally { button.disabled = false; }
});
byId("saved-link").addEventListener("change", event => { byId("checkout").disabled = !event.target.checked; });
byId("checkout").addEventListener("click", async () => {
  if (!pending || !byId("saved-link").checked) return;
  byId("checkout").disabled = true; showError("");
  try {
    const result = await api(`api/questions/${pending.id}/checkout`, {}, pending.token);
    const url = new URL(result.url);
    if (url.protocol !== "https:" || url.hostname !== "checkout.stripe.com") throw new Error("Checkout could not be verified.");
    location.assign(url.href);
  } catch (failure) { showError(failure.message); byId("checkout").disabled = false; }
});
async function load() {
  try {
    catalog = await api("api/catalog");
    for (const [id,key] of [["scope","scope"],["coverage","coverage"],["promise","responsePromise"],["refund","refundPolicy"],["privacy-hint","privacyHint"]]) byId(id).textContent = catalog[key];
    byId("price").textContent = `${new Intl.NumberFormat("en-US",{style:"currency",currency:catalog.currency}).format(catalog.priceCents/100)} · one question`;
    byId("availability").textContent = !catalog.live ? "Test environment—no real payments. Do not enter real customer information." : catalog.accepting ? "Accepting nonmedical questions. Review the scope before paying." : "New questions are paused or the queue is full. Free support remains available.";
    for (const category of catalog.categories) {
      const label = element("label", "", "category-option");
      const radio = document.createElement("input"); radio.type="radio"; radio.name="category"; radio.value=category.id; radio.required=true;
      radio.addEventListener("change", () => selectCategory(category));
      const copy = element("span", ""); copy.append(element("strong",category.title),element("span",category.summary));
      label.append(radio,copy); byId("categories").append(label);
    }
    for (const item of catalog.screening) {
      const label=element("label","","check"); const box=document.createElement("input");
      box.type="checkbox"; box.id=`confirm-${item.id}`; box.required=true;
      label.append(box,element("span",item.text)); byId("confirmations").append(label);
    }
    for (const item of catalog.freeHelp) {
      const detail=element("details",""); detail.append(element("summary",item.title),element("p",item.answer)); byId("free-answers").append(detail);
    }
    byId("intake-fields").disabled = !catalog.accepting;
    try {
      const saved=JSON.parse(sessionStorage.getItem("helpline-pending"));
      if (saved && Date.now()-saved.created < 86400000 && /^[a-f0-9-]{36}$/.test(saved.id) && /^[a-f0-9]{64}$/.test(saved.token)) showPending(saved);
      else sessionStorage.removeItem("helpline-pending");
    } catch { /* Storage is optional. */ }
  } catch { byId("availability").textContent="Online questions are unavailable. No payment can be taken here. Please use free support."; }
}
load();
