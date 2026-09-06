# Solo operating guide

Jahmal uses the signed private iPhone app. Clients use the HTTPS website. The server must remain reachable while the phone is offline. Neither the public website nor the server is installed inside the phone, and no App Store listing is involved.

## Configure the server

Use a dedicated HTTPS origin at its root, Python 3.12, the hash-locked dependencies, a production WSGI process, and private persistent storage. Serve only routes in `server/app.py`; never expose the repository as a static directory. The built-in Flask development server is for local synthetic testing only. Do not put customer data into a development environment.

Set these values through the hosting provider’s secret/configuration controls. Do not paste keys into chat, commit them, put them into a URL, or put a Stripe secret on the iPhone.

| Variable | Meaning |
|---|---|
| `HELPLINE_BASE_URL` | Dedicated public HTTPS origin, with no path/query/credentials; must match the real site |
| `HELPLINE_DATABASE` | Absolute path to SQLite on private persistent storage outside the repository; parent 0700, file 0600 |
| `HELPLINE_ADMIN_TOKEN_SHA256` | SHA-256 digest of a freshly generated random 32-byte token represented as 64 lowercase hex characters; the original token goes only to the iPhone’s private connection field |
| `HELPLINE_RATE_KEY` | Separate random secret of at least 32 characters, for short-lived keyed rate-limit identifiers |
| `STRIPE_SECRET_KEY` | Matching Stripe test or live secret, server only |
| `STRIPE_WEBHOOK_SECRET` | Signing secret for this environment’s webhook endpoint |
| `HELPLINE_LIVE` | `false` for test, `true` only for a configured live service; use a different database and secrets for each |

Generate the device token and rate key with a cryptographically secure password/secret generator. Hash the **64-character token text**, not the underlying raw bytes. Keep the original token in a secure password manager for first connection; its hash alone cannot unlock the app. Use the hosting provider’s secret mechanism rather than shell arguments/history. Stripe test and live credentials must match the mode; the application fails closed otherwise.

Install/run commands after secure environment configuration:

```sh
python -m pip install --require-hashes -r server/requirements.lock
gunicorn --bind 127.0.0.1:8000 --workers 1 --threads 4 --timeout 90 'server.app:create_app()'
```

Put the process behind HTTPS and prevent direct public access to port 8000. Use one shared local database, not ephemeral storage or multiple independent replicas. Keep request/response bodies, tokens and query payloads out of application/proxy/error logs. Add appropriate edge rate limits. The built-in limiter uses the peer IP and ignores untrusted forwarding headers, so a proxy can cause clients to share a bucket; verify this in deployment before opening intake. The process starts with new questions paused on a fresh database.

Register `https://YOUR-SERVICE-ORIGIN/api/stripe/webhook` in the correct Stripe environment for `checkout.session.completed`, `checkout.session.async_payment_succeeded`, `charge.refunded`, `charge.dispute.created`, `charge.dispute.updated`, `charge.dispute.closed`, `refund.created`, `refund.updated` and `refund.failed`. Use the exact signing secret for that endpoint. The server verifies signature and mode, then retrieves the Checkout Session to verify the fixed amount, currency, reference and payment. Replaying events is safe. A private-page refresh can recover a delayed webhook through a fresh Stripe lookup; the browser never declares itself paid.

Stripe-hosted Checkout accepts cards and exposes Apple Pay when eligible. Confirm Apple Pay settings and checkout behavior for this account using [Stripe’s current documentation](https://docs.stripe.com/apple-pay). Do not promise that every device/browser will show Apple Pay. No native Apple merchant identifier or StoreKit configuration belongs in this operator app.

## Install the private iPhone app

Open the Xcode project on a Mac, choose Jahmal’s signing team and connected iPhone, and install the shared app scheme. Complete Apple’s current device/developer-mode steps where required. Manage certificate/provisioning renewal with the chosen signing account; a simulator build is not an installed or permanently signed app. Do not submit it to App Store Connect as part of this workflow.

Set a device passcode. Configure **info@bayareaapps.com** in Apple Mail and verify that it can send and receive. Launch the app, enter the service HTTPS origin and private device token, and unlock using the device’s authentication. The token is not the Stripe key. Verify “Test only” or “Live” matches the intended server. Future unlocks can use the saved Keychain connection with empty fields.

## The client journey

1. Read free emergency/scope guidance and choose one of five topics.
2. Pick a starter question or write one general question; optionally provide minimal nonmedical context and choose checklist/explanation.
3. Enter and confirm the reply email and accept scope, age, terms, response target and refund policy.
4. Prepare checkout. Save the unique private receipt link before proceeding. The server stages the immutable draft; it is not yet paid work.
5. Pay through the same Stripe Checkout Session, with Apple Pay when available. Returning or canceling leads back to the same private link. If uncertain, refresh or ask support, never pay again to recover a question.
6. Read the published answer on the private page or its email copy. Ask one same-topic clarification there by the displayed deadline, without another purchase.

An unpaid draft cannot be edited into a different question after payment. Repeated submit/checkout calls preserve the original reference and session. Identical draft content from the same reply email is blocked from a second purchase within 24 hours. If a client abandons an expired checkout, verify it was unpaid before starting again. A paused queue does not revoke previously opened Stripe sessions; their payments remain obligations.

## Daily work on the iPhone

Refresh the inbox and support mailbox regularly during advertised business days. There are no push notifications or emergency monitoring. The inbox puts unpaid submissions outside the work list and shows work needing attention first, including payment holds, requested refunds and unresolved email. New intake is capped at ten open questions/recent checkout reservations. Pause it before absences or when deadlines cannot be met; paid obligations stay visible.

Read the whole question and context before drafting. If any part needs diagnosis, treatment, interpretation, individualized behavior/health advice or a safety decision, do not answer that part or re-label it as education. Supply a free referral through support and issue a full refund. Do not write a generic disclaimer to satisfy the paid-answer fields. For an eligible question, use its category’s answer goal and the standards in `RESPONSE_TEMPLATES.md`.

Draft the direct answer, practical explanation/checklist, pertinent limit and one to three checked sources. Complete all five human-review confirmations. Drafts are not saved and are discarded when the screen is left or the app locks. Publish only when ready: publication is permanent and starts the clarification window. The server verifies payment again and refuses stale, canceled or held work.

After publication, prepare the email in Apple Mail. Select info@bayareaapps.com as the From address; the app cannot enforce the sender. Review and send. A Mail “sent” result means handed to the mail system, not confirmed delivery. Check your Outbox, Sent folder and bounce messages. The private page already contains the answer even if Mail fails.

Preparing email records an unresolved handoff on the server before Mail opens. If the app is interrupted or the composer is canceled, refresh and inspect Drafts/Outbox/Sent. Confirm either that the email was sent/queued, or that **every unsent copy was deleted**, before another copy is allowed. Do not use clipboard or a second email app to bypass the duplicate check. Resolve the existing handoff before publishing a clarification answer.

## Refunds, lost links and reconciliation

A client’s cancellation before publication immediately blocks the answer and places a refund request in the inbox. Process a full refund, normally within two business days. Scope-only/referral-only outcomes also receive full refunds. The app checks Stripe and uses an idempotency key, so a retry must not become a second refund. A pending/failed result remains work needing attention; check it in Stripe rather than promising a completed bank credit. A dispute, partial refund or externally changed payment needs reconciliation before any answer is published.

For support, match the reference to the payment record and verify control of the original reply mailbox. A screenshot or knowledge of the address alone is insufficient. Do not ask for full card numbers. If a private link is lost, do not demand another purchase. An already-published answer can be handled through the verified original email; honor an included clarification received there without another charge and preserve the support correspondence. The app’s structured clarification form requires the saved link; manual email recovery is a support task, not an automatic reset flow. If the promised service cannot be recovered/provided, issue a full refund after ownership verification.

If a payment succeeds but the database missed its checkout-creation response, the signed webhook can still bind it through the immutable question metadata. For unresolved cases, inspect the exact Stripe Session/reference and retry its webhook; do not manually mark a receipt paid from a screenshot. A response-target miss before a substantive answer is published allows cancellation/refund. Uncertain Stripe or database operations should pause work until reconciled.

## Retention and launch acceptance

Run `flask --app server.app:create_app purge-expired` daily through the host’s scheduler using the same secure environment. Confirm-unpaid expired checkouts become removable after seven days; uncertain creations are retained for manual Stripe reconciliation. Resolved records are removed after 90 days; unfinished answers, refunds and Mail handoffs are preserved. Restrict and expire backups separately, and apply a mailbox/payment-record policy consistent with actual legal/accounting obligations. Test a backup restore before launch.

Before opening live intake, complete one test-mode journey on the actual phone/browser: valid paid question → verified inbox → human answer → private page and support-mail delivery → included clarification → final answer. Separately exercise canceled checkout, delayed webhook, network interruption, duplicate button taps, wrong private link, app background/lock, canceled Mail draft, full refund before answer, and an out-of-scope paid question refund. Check narrow screens, keyboard navigation, large text/VoiceOver, and Apple Pay eligibility with the real account. Confirm unsupported payment devices have the stated card path.

Then verify production HTTPS, private persistent/encrypted storage, restricted logs/backups, secrets, webhook health, correct support mailbox, public policies, business description, refund handling, and the applicable legal boundaries. Use separate live storage/secrets. Live charging is a separate launch step, not implied by a passing unit test, an existing Stripe account, or this review branch. The private iPhone app can be installed without an App Store listing; clients still require the hosted website/API to contact Jahmal.
