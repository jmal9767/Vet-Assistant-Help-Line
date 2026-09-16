/**
 * Cloudflare Worker: Stripe payments for Vet Assistant Help Line.
 *
 * Client flow:
 *   1. Client chooses a fixed service on the public website.
 *   2. /checkout creates a Stripe Checkout Session for that exact service.
 *   3. Stripe returns the client to the website after payment.
 *   4. The website calls /verify before the questionnaire is unlocked.
 *
 * Legacy operator flow remains available at /new and /approve for manually
 * authorized/captured payments.
 *
 * Required configuration:
 *   STRIPE_SECRET_KEY  Stripe secret key (Secret)
 *   OPERATOR_KEY       private operator key (Secret)
 *   SITE_URL           https://jmal9767.github.io/Vet-Assistant-Help-Line/
 *   ALLOWED_ORIGIN     https://jmal9767.github.io
 *
 * Required binding for the legacy hold/capture flow:
 *   PAYMENTS           Cloudflare KV namespace
 */

const AUTO_CAPTURE_HOURS = 24;
const CHECKOUT_EXPIRE_DAYS = 2;

const SERVICES = {
  "quick-email": {
    label: "Quick question — email",
    amount: 10,
    allowsSpeed: true,
  },
  "detailed-email": {
    label: "Detailed question — email",
    amount: 20,
    allowsSpeed: true,
  },
  "quick-text": {
    label: "Quick question — text",
    amount: 15,
    allowsSpeed: true,
  },
  "live-text": {
    label: "Live text chat — 15 minutes",
    amount: 25,
    allowsSpeed: false,
  },
  "quick-call": {
    label: "Quick call — 15 minutes",
    amount: 30,
    allowsSpeed: false,
  },
  "full-consult": {
    label: "Full consult — 30 minutes",
    amount: 45,
    allowsSpeed: false,
  },
};

const SPEEDS = {
  standard: { label: "Standard", amount: 0 },
  "same-day": { label: "Same-day reply", amount: 10 },
  express: { label: "Express reply (2–4 hours)", amount: 20 },
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders(env),
      });
    }

    if (url.pathname === "/checkout" && request.method === "GET") {
      return handleCheckout(url, env);
    }
    if (url.pathname === "/verify" && request.method === "GET") {
      return handleVerify(url, env);
    }

    // Legacy operator-only flow.
    if (url.pathname === "/new" && request.method === "GET") {
      return handleNew(url, env);
    }
    if (url.pathname === "/approve" && request.method === "GET") {
      return handleApprove(url, env);
    }

    return html("Not found", 404);
  },

  async scheduled(_event, env) {
    await autoCapture(env);
  },
};

async function handleCheckout(url, env) {
  const serviceId = url.searchParams.get("service") || "";
  const speedId = url.searchParams.get("speed") || "standard";
  const service = SERVICES[serviceId];
  const speed = SPEEDS[speedId];

  if (!service) {
    return html("That service option is not valid.", 400);
  }
  if (!speed) {
    return html("That reply-speed option is not valid.", 400);
  }
  if (!service.allowsSpeed && speedId !== "standard") {
    return html("Faster-reply add-ons are only available for email or quick text answers.", 400);
  }

  const amount = service.amount + speed.amount;
  const description =
    speedId === "standard"
      ? service.label
      : service.label + " · " + speed.label;

  const siteUrl = normalizedSiteUrl(env.SITE_URL);

  const session = await stripe(env, "POST", "/v1/checkout/sessions", {
    mode: "payment",
    "line_items[0][quantity]": "1",
    "line_items[0][price_data][currency]": "usd",
    "line_items[0][price_data][unit_amount]": String(amount * 100),
    "line_items[0][price_data][product_data][name]": description,
    "metadata[service]": serviceId,
    "metadata[speed]": speedId,
    "payment_intent_data[metadata][service]": serviceId,
    "payment_intent_data[metadata][speed]": speedId,
    success_url:
      siteUrl +
      "?checkout=success&session_id={CHECKOUT_SESSION_ID}",
    cancel_url: siteUrl + "?checkout=canceled",
  });

  if (session.error || !session.url) {
    return html(
      "Stripe could not start checkout. Please try again in a few minutes.",
      502
    );
  }

  return Response.redirect(session.url, 303);
}

async function handleVerify(url, env) {
  const id = url.searchParams.get("id") || "";

  if (!id.startsWith("cs_")) {
    return json(
      { paid: false, error: "Invalid checkout session." },
      400,
      env
    );
  }

  const session = await stripe(
    env,
    "GET",
    "/v1/checkout/sessions/" + encodeURIComponent(id)
  );

  if (session.error) {
    return json(
      { paid: false, error: "Checkout session not found." },
      404,
      env
    );
  }

  const serviceId = session.metadata?.service || "";
  const speedId = session.metadata?.speed || "standard";
  const service = SERVICES[serviceId];
  const speed = SPEEDS[speedId];

  if (!service || !speed) {
    return json(
      { paid: false, error: "Checkout details could not be verified." },
      409,
      env
    );
  }

  const expectedAmount =
    (service.amount + (service.allowsSpeed ? speed.amount : 0)) * 100;

  if (
    session.payment_status !== "paid" ||
    Number(session.amount_total) !== expectedAmount
  ) {
    return json(
      { paid: false, paymentStatus: session.payment_status || "unpaid" },
      402,
      env
    );
  }

  return json(
    {
      paid: true,
      sessionId: session.id,
      service: serviceId,
      serviceLabel: service.label,
      speed: speedId,
      speedLabel: speed.label,
      amount: expectedAmount / 100,
    },
    200,
    env
  );
}

/** Legacy operator flow: /new?key=…&amount=20&desc=Detailed+question */
async function handleNew(url, env) {
  if (url.searchParams.get("key") !== env.OPERATOR_KEY) {
    return html("Unauthorized", 401);
  }

  const amount = Number(url.searchParams.get("amount"));
  const desc = (url.searchParams.get("desc") || "Help line answer").slice(
    0,
    120
  );
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
    success_url: normalizedSiteUrl(env.SITE_URL) + "?paid=1",
    cancel_url: normalizedSiteUrl(env.SITE_URL),
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
  const approveLink =
    url.origin + "/approve?id=" + session.id + "&t=" + approveToken;

  return html(`
    <h2>Payment created — ${escapeHtml(desc)} · $${amount}</h2>
    <p><strong>1. Send this payment link to the client now</strong> (their card is authorized but not captured yet):</p>
    <p><a href="${session.url}">${session.url}</a></p>
    <p><strong>2. Put this approval link at the end of your answer</strong>:</p>
    <p><a href="${approveLink}">${approveLink}</a></p>
    <p>If the client does not tap it, the payment completes automatically after
    ${AUTO_CAPTURE_HOURS} hours.</p>
  `);
}

async function handleApprove(url, env) {
  const id = url.searchParams.get("id") || "";
  const token = url.searchParams.get("t") || "";

  if (!id.startsWith("cs_") || token !== (await sign(id, env))) {
    return html("This link isn't valid.", 400);
  }

  const session = await stripe(env, "GET", "/v1/checkout/sessions/" + id);
  if (session.error || !session.payment_intent) {
    return html(
      "We couldn't find this payment — it may not be completed yet.",
      404
    );
  }

  const intent = await stripe(
    env,
    "GET",
    "/v1/payment_intents/" + session.payment_intent
  );

  if (intent.status === "succeeded") {
    return html(
      "<h2>✅ All set</h2><p>This payment was already completed. Thank you!</p>"
    );
  }

  if (intent.status !== "requires_capture") {
    return html(
      "This payment isn't ready to complete (status: " +
        escapeHtml(intent.status) +
        ").",
      409
    );
  }

  const captured = await stripe(
    env,
    "POST",
    "/v1/payment_intents/" + intent.id + "/capture"
  );

  if (captured.error) {
    return html(
      "Sorry — the payment couldn't be completed. Please try again later.",
      502
    );
  }

  await env.PAYMENTS.delete("cs:" + id);
  return html(
    "<h2>✅ Thank you!</h2><p>Your payment is complete.</p>"
  );
}

async function autoCapture(env) {
  if (!env.PAYMENTS) return;

  const list = await env.PAYMENTS.list({ prefix: "cs:" });

  for (const key of list.keys) {
    const id = key.name.slice(3);
    const session = await stripe(env, "GET", "/v1/checkout/sessions/" + id);
    if (session.error) continue;

    if (!session.payment_intent) {
      const meta = JSON.parse(
        (await env.PAYMENTS.get(key.name)) || "{}"
      );
      if (
        Date.now() - (meta.createdAt || 0) >
        CHECKOUT_EXPIRE_DAYS * 86400000
      ) {
        await env.PAYMENTS.delete(key.name);
      }
      continue;
    }

    const intent = await stripe(
      env,
      "GET",
      "/v1/payment_intents/" + session.payment_intent
    );

    if (intent.status === "requires_capture") {
      const ageHours = (Date.now() / 1000 - intent.created) / 3600;
      if (ageHours >= AUTO_CAPTURE_HOURS) {
        const captured = await stripe(
          env,
          "POST",
          "/v1/payment_intents/" + intent.id + "/capture"
        );
        if (!captured.error) {
          await env.PAYMENTS.delete(key.name);
        }
      }
    } else if (
      intent.status === "succeeded" ||
      intent.status === "canceled"
    ) {
      await env.PAYMENTS.delete(key.name);
    }
  }
}

async function stripe(env, method, path, params) {
  const options = {
    method,
    headers: {
      Authorization: "Bearer " + env.STRIPE_SECRET_KEY,
    },
  };

  if (params) {
    options.headers["Content-Type"] =
      "application/x-www-form-urlencoded";
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
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(value)
  );
  return [...new Uint8Array(mac)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .slice(0, 32);
}

function normalizedSiteUrl(siteUrl) {
  const value =
    siteUrl ||
    "https://jmal9767.github.io/Vet-Assistant-Help-Line/";
  return value.endsWith("/") ? value : value + "/";
}

function corsHeaders(env) {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Cache-Control": "no-store",
  };
}

function json(payload, status, env) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(env),
    },
  });
}

function escapeHtml(text) {
  return String(text).replace(
    /[<>&"]/g,
    (c) =>
      ({
        "<": "&lt;",
        ">": "&gt;",
        "&": "&amp;",
        '"': "&quot;",
      })[c]
  );
}

function html(body, status = 200) {
  return new Response(
    `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Vet Assistant Help Line</title>
    <style>body{font-family:-apple-system,sans-serif;max-width:600px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#14181c}
    a{color:#1f3a5f;word-break:break-all}h2{color:#1f3a5f}</style></head><body>${body}</body></html>`,
    {
      status,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Cache-Control": "no-store",
      },
    }
  );
}
