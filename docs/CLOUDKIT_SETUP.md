# CloudKit Setup — website form → your operator app

The pipeline is:

```
Client fills the website form
        │  (HTTPS POST)
        ▼
Cloudflare Worker (free)  ──  writes a "Question" record  ──▶  CloudKit public database
                                                                      │
                                                                      ▼
                                                    Your iPhone app (inbox + push notification)
```

The Worker is needed because Apple only lets **authenticated users** write to
CloudKit from the web — anonymous visitors can't. The Worker holds a
server-to-server key and writes on their behalf. Clients never need an Apple ID
and Android works fine.

Everything below is one-time setup, roughly 30–45 minutes.

## 1. Apple Developer + Xcode (~10 min)

You need a paid [Apple Developer Program](https://developer.apple.com/programs/)
membership ($99/yr) — CloudKit and push notifications aren't available on free
accounts.

In Xcode, select the **VetAssistantHelpLine** target → **Signing & Capabilities**:

1. Keep **Bundle Identifier** as `com.jmal9767.VetAssistantHelpLine`.
2. Select **Bay Area Apps LLC**, team `XF8WR8DG9P`.
3. Click **+ Capability** and add **iCloud** → check **CloudKit**. Xcode should
   use `iCloud.com.jmal9767.VetAssistantHelpLine`, which is already specified
   in `VetAssistantHelpLine.entitlements`.
4. Add **Push Notifications**.
5. Add **Background Modes** → check **Remote notifications**.

The container and Development schema already exist. Run the app on an iPhone
signed in to the iCloud account that will answer client questions. The app's
iCloud user and the Apple Developer account can be different accounts.

## 2. CloudKit Console: schema (~10 min)

Open [CloudKit Console](https://icloud.developer.apple.com/) → your container →
**Development** environment.

Use the exact field mapping in [Question schema](QUESTION_SCHEMA.md), which
matches the current intake form, relay, and operator app. Confirm the selected
Apple Developer team matches your app before creating or changing a container.

1. **Schema → Record Types → New Type**: `Question` with these fields, all type
   **String** except where noted:
   - `name`, `email`, `phone`, `species`, `age`, `category`, `question`, `status`
   - `submittedAt` — type **Date/Time**
   - `phone` is optional and must remain a String to preserve `+` and leading
     zeroes. The relay sets `status` to `new` and supplies `submittedAt`.
2. **Indexes** on `Question`:
   - `recordName` → **Queryable**
   - `submittedAt` → **Queryable** and **Sortable**
3. **Schema → Security Roles**: inspect existing permissions first. Use a
   dedicated operator role with **Read** and **Write** on `Question`, assigned
   only to your operator iCloud user. Give the relay's server-to-server role
   **Create**, **Read**, and **Write** so it can validate a question-specific
   checkout, create intake records, and record verified PayPal/Apple Pay status
   changes. Keep the server key private. Do not grant World or Authenticated general Read
   or Write access: **Authenticated means all authenticated iCloud users, not
   just you**. Questions contain private client contact information.

## 3. Server-to-server key (~5 min)

In Terminal:

```bash
# Run in a private folder outside the Git repository.
umask 077
# Generate the key pair
openssl ecparam -name prime256v1 -genkey -noout -out eckey.pem
# Public key — paste this into CloudKit Console
openssl ec -in eckey.pem -pubout
# PKCS#8 version of the private key — the Worker needs this one
openssl pkcs8 -topk8 -nocrypt -in eckey.pem -out eckey-pkcs8.pem
```

In CloudKit Console → **Tokens & Keys** (sometimes “API Access”) → **Server-to-Server Keys**
→ create a key, paste in the *public* key output. Copy the generated **Key ID**.

Keep `eckey.pem` / `eckey-pkcs8.pem` private — never commit them to the repo.

## 4. Deploy the Cloudflare Worker (~10 min)

The local [`relay/wrangler.jsonc`](../relay/wrangler.jsonc) now selects the
existing relay, the correct container, the Development environment, and the
website origin. This file is prepared locally; the Worker has not been deployed.

With Node.js/npm installed, open Terminal in the repository and run:

```bash
cd relay
npx wrangler login
npx wrangler deploy
npx wrangler secret put CLOUDKIT_KEY_ID
npx wrangler secret put CLOUDKIT_PRIVATE_KEY
```

The login opens Cloudflare's sign-in page. Deploy prints the Worker URL. For
`CLOUDKIT_KEY_ID`, enter the key ID from Apple. For `CLOUDKIT_PRIVATE_KEY`, provide
the complete contents of `eckey-pkcs8.pem`, including the BEGIN/END lines. You can
also add the multiline private key in the dashboard instead of using the final
command: **Workers & Pages → vet-helpline-development → Settings → Variables and
Secrets → Add → Secret**, then **Deploy**. Until both credentials are configured,
the relay cannot submit questions to CloudKit.

The complete settings are:

   | Name | Value |
   |------|-------|
   | `CLOUDKIT_CONTAINER` | `iCloud.com.jmal9767.VetAssistantHelpLine` |
   | `CLOUDKIT_ENVIRONMENT` | `development` (switch to `production` after you deploy the schema) |
   | `CLOUDKIT_KEY_ID` | the Key ID from step 3 |
   | `CLOUDKIT_PRIVATE_KEY` | the full contents of `eckey-pkcs8.pem` (mark as **Secret**) |
   | `ALLOWED_ORIGIN` | `https://jmal9767.github.io` |

Copy the actual Worker URL printed by deployment; do not use the example URL
literally. See [Cloudflare deployment configuration](https://developers.cloudflare.com/workers/wrangler/configuration/)
and [adding secrets](https://developers.cloudflare.com/workers/configuration/secrets/).

## 5. Point the website at the Worker (~2 min)

In `index.html`, set:

```js
var WORKER_URL = "https://vet-helpline.<you>.workers.dev";
```

Optionally set `HELPLINE_EMAIL` as a fallback shown if a submission fails.
Commit and push — GitHub Pages redeploys automatically.

## 6. Test end-to-end

1. Submit a test question on the website — you should see “Question sent!”.
2. Open the app → Inbox → pull to refresh. The question should appear under **New**.
3. If push is set up, submitting another question should buzz your phone.

## Going live

When everything works, in CloudKit Console use **Deploy Schema Changes…** to
push the schema from Development to **Production**, change the Worker's
`CLOUDKIT_ENVIRONMENT` to `production`, and build the app in Release (Xcode
automatically uses the production CloudKit environment for App Store /
TestFlight builds).

## Troubleshooting

- **Worker returns 502 / “Could not save the question”** — check the Worker's
  live logs; the CloudKit error is printed there. `AUTHENTICATION_FAILED`
  usually means the Key ID and private key don't match, or the container/
  environment names are wrong.
- **App shows nothing but the website says sent** — confirm the app and Worker
  use the same container *and* environment (a Debug build talks to
  `development`, TestFlight/App Store builds talk to `production`).
- **“Did not find record type: Question”** — the schema step was skipped in the
  environment the Worker is writing to.
- **No push notifications** — notifications require the paid team's push
  entitlement; also check iOS Settings → Notifications for the app. Pull to
  refresh always works regardless.
