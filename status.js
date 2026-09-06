"use strict";
const $ = id => document.getElementById(id);
const [id,token] = location.hash.slice(1).split("/");
const valid = /^[a-f0-9-]{36}$/.test(id || "") && /^[a-f0-9]{64}$/.test(token || "");
let current;
const labels={pending:"Awaiting verified payment",paid:"Paid · awaiting human review",answered:"Your answer is ready",clarification:"Clarification awaiting reply",closed:"Answer and clarification complete",refund_requested:"Refund requested · processing or review pending",refunded:"Refund processed by Stripe",payment_hold:"Payment needs reconciliation",expired:"Checkout expired"};
const date = value => new Intl.DateTimeFormat("en-US",{dateStyle:"medium",timeStyle:"short",timeZone:"America/Los_Angeles"}).format(new Date(value*1000))+" Pacific Time";
async function api(suffix="",body) {
  if (!valid) throw new Error("Open your complete private question link. For a lost link, contact free support with your receipt reference.");
  const response=await fetch(`api/questions/${id}${suffix}`,{method:body?"POST":"GET",credentials:"omit",cache:"no-store",headers:{"Content-Type":"application/json","X-Question-Token":token},body:body?JSON.stringify(body):undefined});
  const result=await response.json(); if (!response.ok) throw new Error(result.error || "Question unavailable."); return result;
}
function renderAnswer(target,answer) {
  const root=$(target); root.replaceChildren();
  for (const key of ["summary","practical","boundary"]) { const p=document.createElement("p");p.textContent=answer[key];p.className="preserve-lines";root.append(p); }
  const list=document.createElement("ul");
  for (const url of answer.sources) {
    const parsed=new URL(url); if(parsed.protocol!=="https:") continue;
    const item=document.createElement("li"),link=document.createElement("a");link.href=parsed.href;link.textContent=parsed.hostname;link.rel="noopener noreferrer";link.target="_blank";item.append(link);list.append(item);
  } root.append(list);
}
async function refresh() {
  $("refresh").disabled=true;$("error").textContent="";
  try {
    current=await api();$("details").hidden=false;$("message").textContent="Status checked. Payment is verified by the server, not by this page.";
    if(current.state!=="pending") { try { const saved=JSON.parse(sessionStorage.getItem("helpline-pending")); if(saved?.id===id) sessionStorage.removeItem("helpline-pending"); } catch { /* Optional tab storage. */ } }
    $("state").textContent=labels[current.state] || "Contact support";$("reference").textContent=`Reference: ${current.id}`;$("question").textContent=current.question;$("note").textContent=current.note;
    $("due").textContent=current.due ? `Response target: ${date(current.clarification_due || current.due)}` : "Payment may still be confirming. Do not create another purchase if you were charged.";
    $("checkout").hidden=current.state!=="pending";$("cancel").hidden=current.state!=="paid" || Boolean(current.answer);
    $("new-question").hidden=!["answered","closed","refunded","expired"].includes(current.state);
    if(current.state==="expired") { $("due").textContent="Stripe confirmed this checkout expired without payment."; $("new-question").textContent="Start a new unpaid draft"; }
    $("answer").hidden=!current.answer;if(current.answer) renderAnswer("answer-body",current.answer);
    $("clarification-answer").hidden=!current.clarification_answer;if(current.clarification_answer) renderAnswer("clarification-body",current.clarification_answer);
    $("clarification-form").hidden=current.state!=="answered" || Boolean(current.clarification) || Date.now()/1000>current.clarification_deadline;
    $("clarification-deadline").textContent=current.clarification_deadline ? `Request by ${date(current.clarification_deadline)}. No new payment is needed.` : "";
  } catch(error) {$("error").textContent=error.message;$("message").textContent="Status could not be verified. No payment action was taken.";}
  finally {$("refresh").disabled=false;}
}
$("refresh").addEventListener("click",refresh);
$("checkout").addEventListener("click",async()=>{
  $("checkout").disabled=true;
  try{const result=await api("/checkout",{});const url=new URL(result.url);if(url.protocol!=="https:"||url.hostname!=="checkout.stripe.com")throw new Error("Invalid checkout destination.");location.assign(url.href);}
  catch(error){$("error").textContent=error.message;$("checkout").disabled=false;}
});
$("cancel").addEventListener("click",async()=>{
  if(!window.confirm("Request a full refund and stop work on this unanswered question?"))return;
  $("cancel").disabled=true;
  try{await api("/refund-request",{});await refresh();}catch(error){$("error").textContent=error.message;}finally{$("cancel").disabled=false;}
});
$("clarification-form").addEventListener("submit",async event=>{
  event.preventDefault();const button=event.target.querySelector("button");button.disabled=true;
  try{await api("/clarification",{text:$("clarification").value,sameTopic:$("same-topic").checked});await refresh();}catch(error){$("error").textContent=error.message;}finally{button.disabled=false;}
});
refresh();
