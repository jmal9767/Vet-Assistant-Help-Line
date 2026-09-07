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

1. Set **Bundle Identifier** to something you own, e.g.
   `com.jmal9767.VetAssistantHelpLine` (don't ship `com.example.…` — CloudKit
   container names are global).
2. Make sure your **Team** is selected.
3. Click **+ Capability** and add **iCloud** → check **CloudKit**. Xcode should
   pick up the container `iCloud.<your bundle id>` from the existing
   `VetAssistantHelpLine.entitlements` file (it uses `iCloud.$(CFBundleIdentifier)`).
4. Add **Push Notifications**.
5. Add **Background Modes** → check **Remote notifications**.

Run the app once on your device — this creates the CloudKit container.

## 2. CloudKit Console: schema (~10 min)

Open [CloudKit Console](https://icloud.developer.apple.com/) → your container →
**Development** environment.

1. **Schema → Record Types → New Type**: `Question` with these fields, all type
   **String** except where noted:
   - `name`, `email`, `species`, `age`, `category`, `question`, `status`
   - `submittedAt` — type **Date/Time**
2. **Indexes** on `Question`:
   - `recordName` → **Queryable**
   - `submittedAt` → **Queryable** and **Sortable**
3. **Schema → Security Roles**: for `Question`, give **Authenticated** →
   **Read** and **Write**. Do **not** give World read access — that would make
   client questions (and their email addresses) publicly readable. "Authenticated"
   effectively means *you*, since only your app queries this container.

## 3. Server-to-server key (~5 min)

In Terminal:

```bash
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

1. Create a free account at [cloudflare.com](https://dash.cloudflare.com/), go to
   **Workers & Pages** → **Create Worker**.
2. Paste in the contents of [`relay/cloudkit-worker.js`](../relay/cloudkit-worker.js)
   and deploy.
3. In the Worker's **Settings → Variables and Secrets**, add:

   | Name | Value |
   |------|-------|
   | `CLOUDKIT_CONTAINER` | `iCloud.<your bundle id>`, e.g. `iCloud.com.jmal9767.VetAssistantHelpLine` |
   | `CLOUDKIT_ENVIRONMENT` | `development` (switch to `production` after you deploy the schema) |
   | `CLOUDKIT_KEY_ID` | the Key ID from step 3 |
   | `CLOUDKIT_PRIVATE_KEY` | the full contents of `eckey-pkcs8.pem` (mark as **Secret**) |
   | `ALLOWED_ORIGIN` | `https://jmal9767.github.io` |

4. Copy the Worker URL (e.g. `https://vet-helpline.<you>.workers.dev`).

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
