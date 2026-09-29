/**
 * Retired Stripe worker. Do not deploy this file.
 *
 * Payments now go through PayPal, Apple Pay, and Cash App in cloudkit-worker.js.
 * This worker used to authorize a card and capture it automatically after 24 hours
 * even when no answer had been sent. Creating a new charge and the hourly capture
 * are both disabled so a leftover deploy cannot bill a client on a timer.
 *
 * An approval link that was already sent can still capture that one existing
 * authorization if this worker is still deployed. New /new links are refused.
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/new") {
      return handleNew(url, env);
    }
    if (url.pathname === "/approve") {
      return handleApprove(url, env);
    }
    return html("Not found", 404);
  },

  async scheduled() {
    // Intentionally empty. Automatic capture billed clients even when no answer was sent.
  },
};

/** Operator creates a payment: /new?key=…&amount=20&desc=Detailed+question */
async function handleNew() {
  return html(
    "<h2>This payment link is retired</h2><p>New card holds are not created here. Use the care line website, which checks out with PayPal or Apple Pay, or confirm a Cash App payment in the operator app.</p>",
    410
  );
}

/** Client approves: /approve?id=cs_…&t=… — captures the payment. */
async function handleApprove(url, env) {
  const id = url.searchParams.get("id") || "";
  const token = url.searchParams.get("t") || "";
  if (!id.startsWith("cs_") || token !== (await sign(id, env))) {
    return html("This link isn't valid.", 400);
  }

  const session = await stripe(env, "GET", "/v1/checkout/sessions/" + id);
  if (session.error || !session.payment_intent) {
    return html("We couldn't find this payment — it may not be completed yet.", 404);
  }

  const intent = await stripe(env, "GET", "/v1/payment_intents/" + session.payment_intent);
  if (intent.status === "succeeded") {
    return html("<h2>✅ All set</h2><p>This payment was already completed. Thank you!</p>");
  }
  if (intent.status !== "requires_capture") {
    return html("This payment isn't ready to complete (status: " + escapeHtml(intent.status) + ").", 409);
  }

  const captured = await stripe(env, "POST", "/v1/payment_intents/" + intent.id + "/capture");
  if (captured.error) {
    return html("Sorry — the payment couldn't be completed. Please try again later.", 502);
  }
  await env.PAYMENTS.delete("cs:" + id);
  return html("<h2>✅ Thank you!</h2><p>Your payment is complete. We're glad the care line could help — come back any time.</p>");
}

async function stripe(env, method, path, params) {
  const options = {
    method,
    headers: { Authorization: "Bearer " + env.STRIPE_SECRET_KEY },
  };
  if (params) {
    options.headers["Content-Type"] = "application/x-www-form-urlencoded";
    options.body = new URLSearchParams(params).toString();
  }
  const response = await fetch("https://api.stripe.com" + path, options);
  return response.json();
}

async function sign(value, env) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.OPERATOR_KEY),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

function escapeHtml(text) {
  return text.replace(/[<>&"]/g, (c) => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;" })[c]);
}

function html(body, status = 200) {
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Paws & Whiskers Care Line</title>
    <style>body{font-family:-apple-system,sans-serif;max-width:600px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#14181c}
    a{color:#1f3a5f;word-break:break-all}h2{color:#1f3a5f}</style></head><body>${body}</body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}
