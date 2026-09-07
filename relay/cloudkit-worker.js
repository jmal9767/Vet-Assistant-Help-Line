/**
 * Cloudflare Worker: receives help-line form submissions from the website
 * and creates a "Question" record in the CloudKit public database using a
 * CloudKit server-to-server key.
 *
 * Required secrets/vars (set with `wrangler secret put <NAME>` or in the dashboard):
 *   CLOUDKIT_CONTAINER   e.g. "iCloud.com.jmal9767.VetAssistantHelpLine"
 *   CLOUDKIT_ENVIRONMENT "development" or "production"
 *   CLOUDKIT_KEY_ID      the key ID shown in CloudKit Console → Tokens & Keys
 *   CLOUDKIT_PRIVATE_KEY the PKCS#8 private key PEM (contents of eckey-pkcs8.pem)
 *   ALLOWED_ORIGIN       e.g. "https://jmal9767.github.io" (or "*" while testing)
 *
 * See docs/CLOUDKIT_SETUP.md for the full setup walkthrough.
 */

const MAX_LENGTHS = { name: 100, email: 200, species: 60, age: 60, category: 80, question: 4000 };

export default {
  async fetch(request, env) {
    const cors = corsHeaders(env);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }
    if (request.method !== "POST") {
      return json({ error: "Method not allowed" }, 405, cors);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON" }, 400, cors);
    }

    // Honeypot field filled in → almost certainly a bot. Pretend success.
    if (body.website) {
      return json({ ok: true }, 200, cors);
    }

    const fields = {};
    for (const key of ["name", "email", "species", "age", "category", "question"]) {
      const value = String(body[key] ?? "").trim().slice(0, MAX_LENGTHS[key]);
      if (!value && key !== "age") {
        return json({ error: `Missing field: ${key}` }, 400, cors);
      }
      fields[key] = value;
    }

    const requestBody = JSON.stringify({
      operations: [
        {
          operationType: "create",
          record: {
            recordType: "Question",
            fields: {
              name: { value: fields.name },
              email: { value: fields.email },
              species: { value: fields.species },
              age: { value: fields.age || "Not given" },
              category: { value: fields.category },
              question: { value: fields.question },
              status: { value: "new" },
              submittedAt: { value: Date.now(), type: "TIMESTAMP" },
            },
          },
        },
      ],
    });

    const path = `/database/1/${env.CLOUDKIT_CONTAINER}/${env.CLOUDKIT_ENVIRONMENT}/public/records/modify`;
    const headers = await signedHeaders(env, path, requestBody);

    const ckResponse = await fetch(`https://api.apple-cloudkit.com${path}`, {
      method: "POST",
      headers,
      body: requestBody,
    });

    if (!ckResponse.ok) {
      console.error("CloudKit error", ckResponse.status, await ckResponse.text());
      return json({ error: "Could not save the question" }, 502, cors);
    }

    const result = await ckResponse.json();
    const recordError = result.records?.find((r) => r.serverErrorCode);
    if (recordError) {
      console.error("CloudKit record error", JSON.stringify(recordError));
      return json({ error: "Could not save the question" }, 502, cors);
    }

    return json({ ok: true }, 200, cors);
  },
};

function corsHeaders(env) {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function json(payload, status, cors) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json", ...cors },
  });
}

/**
 * CloudKit server-to-server auth: sign
 *   "<ISO8601 date>:<base64 SHA-256 of body>:<request path>"
 * with the ECDSA P-256 key, and send the DER-encoded signature.
 */
async function signedHeaders(env, path, requestBody) {
  // CloudKit requires seconds precision, no milliseconds.
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");

  const bodyHash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(requestBody));
  const message = `${date}:${toBase64(bodyHash)}:${path}`;

  const key = await importPrivateKey(env.CLOUDKIT_PRIVATE_KEY);
  const rawSignature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(message)
  );

  return {
    "Content-Type": "application/json",
    "X-Apple-CloudKit-Request-KeyID": env.CLOUDKIT_KEY_ID,
    "X-Apple-CloudKit-Request-ISO8601Date": date,
    "X-Apple-CloudKit-Request-SignatureV1": toBase64(p1363ToDer(new Uint8Array(rawSignature))),
  };
}

async function importPrivateKey(pem) {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

// WebCrypto emits ECDSA signatures as raw r||s (IEEE P1363); CloudKit expects ASN.1 DER.
function p1363ToDer(signature) {
  const encodeInteger = (bytes) => {
    let start = 0;
    while (start < bytes.length - 1 && bytes[start] === 0) start++;
    let value = bytes.slice(start);
    if (value[0] & 0x80) value = new Uint8Array([0, ...value]);
    return new Uint8Array([0x02, value.length, ...value]);
  };
  const r = encodeInteger(signature.slice(0, 32));
  const s = encodeInteger(signature.slice(32));
  return new Uint8Array([0x30, r.length + s.length, ...r, ...s]);
}

function toBase64(buffer) {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)));
}
