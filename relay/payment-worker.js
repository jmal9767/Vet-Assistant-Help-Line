/**
 * Cloudflare Worker: hold-until-satisfied payments for the help line.
 *
 * Flow:
 *   1. Operator opens  /new?key=<OPERATOR_KEY>&amount=20&desc=Detailed+question
 *      → gets a Stripe Checkout link (card AUTHORIZED, not charged) to send to
 *        the client, plus an approval link to include in the answer.
 *   2. Client pays → the card is authorized (funds held, nothing captured).
 *   3. Operator answers the question and includes the approval link.
 *      Client taps it → the payment is captured ("goes through").
 *   4. If the client doesn't respond, a scheduled cron capture runs the
 *      payment automatically once it is older than AUTO_CAPTURE_HOURS.
 *
 * Required configuration (Worker → Settings → Variables and Secrets):
 *   STRIPE_SECRET_KEY  your Stripe secret key (sk_live_… / sk_test_…) — Secret
 *   OPERATOR_KEY       a long random string only you know — Secret
 *   SITE_URL           e.g. "https://jmal9767.github.io/Vet-Assistant-Help-Line/"
 *
 * Required bindings:
 *   PAYMENTS           a KV namespace (Workers → KV) bound as "PAYMENTS"
 *
 * Required trigger:
 *   Cron trigger, e.g. every hour: "0 * * * *"
 *
 * See docs/PAYMENTS_SETUP.md for the full walkthrough.
 */

const AUTO_CAPTURE_HOURS = 24;
const CHECKOUT_EXPIRE_DAYS = 2; // give up on sessions never paid after this

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

  async scheduled(_event, env) {
    await autoCapture(env);
  },
};

/** Operator creates a payment: /new?key=…&amount=20&desc=Detailed+question */
async function handleNew(url, env) {
  if (url.searchParams.get("key") !== env.OPERATOR_KEY) {
    return html("Unauthorized", 401);
  }

  const amount = Number(url.searchParams.get("amount"));
  const desc = (url.searchParams.get("desc") || "Help line answer").slice(0, 120);
  if (!Number.isFinite(amount) || amount < 1 || amount > 500) {
    return html("Amount must be between 1 and 500 (whole dollars).", 400);
  }

  const session = await stripe(env, "POST", "/v1/checkout/sessions", {
    mode: "payment",
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": "usd",
    "line_items[0][price_data][unit_amount]": String(Math.round(amount * 100)),
    "line_items[0][price_data][product_data][name]": desc,
    "payment_intent_data[capture_method]": "manual",
    success_url: env.SITE_URL + "?paid=1",
    cancel_url: env.SITE_URL,
  });
  if (session.error) {
    return html("Stripe error: " + session.error.message, 502);
  }

  await env.PAYMENTS.put(
    "cs:" + session.id,
    JSON.stringify({ createdAt: Date.now(), desc, amount }),
    { expirationTtl: 60 * 60 * 24 * 14 }
  );

  const approveToken = await sign(session.id, env);
  const approveLink = url.origin + "/approve?id=" + session.id + "&t=" + approveToken;

  return html(`
    <h2>Payment created — ${escapeHtml(desc)} · $${amount}</h2>
    <p><strong>1. Send this payment link to the client now</strong> (they pay, the card is only authorized):</p>
    <p><a href="${session.url}">${session.url}</a></p>
    <p><strong>2. Put this approval link at the end of your answer</strong>
    ("Happy with the answer? Tap here to complete your payment"):</p>
    <p><a href="${approveLink}">${approveLink}</a></p>
    <p>If the client doesn't tap it, the payment completes automatically after
    ${AUTO_CAPTURE_HOURS} hours.</p>
  `);
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
  return html("<h2>✅ Thank you!</h2><p>Your payment is complete. We're glad the help line could help — come back any time.</p>");
}

/** Cron: capture anything authorized more than AUTO_CAPTURE_HOURS ago. */
async function autoCapture(env) {
  const list = await env.PAYMENTS.list({ prefix: "cs:" });
  for (const key of list.keys) {
    const id = key.name.slice(3);
    const session = await stripe(env, "GET", "/v1/checkout/sessions/" + id);
    if (session.error) continue;

    if (!session.payment_intent) {
      // Never paid; drop stale sessions.
      const meta = JSON.parse((await env.PAYMENTS.get(key.name)) || "{}");
      if (Date.now() - (meta.createdAt || 0) > CHECKOUT_EXPIRE_DAYS * 86400000) {
        await env.PAYMENTS.delete(key.name);
      }
      continue;
    }

    const intent = await stripe(env, "GET", "/v1/payment_intents/" + session.payment_intent);
    if (intent.status === "requires_capture") {
      const ageHours = (Date.now() / 1000 - intent.created) / 3600;
      if (ageHours >= AUTO_CAPTURE_HOURS) {
        const captured = await stripe(env, "POST", "/v1/payment_intents/" + intent.id + "/capture");
        if (!captured.error) await env.PAYMENTS.delete(key.name);
      }
    } else if (intent.status === "succeeded" || intent.status === "canceled") {
      await env.PAYMENTS.delete(key.name);
    }
  }
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
    <title>Vet Assistant Help Line</title>
    <style>body{font-family:-apple-system,sans-serif;max-width:600px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#14181c}
    a{color:#1f3a5f;word-break:break-all}h2{color:#1f3a5f}</style></head><body>${body}</body></html>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } }
  );
}
