> Updated October 5, 2026: new written requests use **private website conversations** answered directly in the app. Email/Text references below apply to historical requests or optional integrations. See [private conversations](PRIVATE_CONVERSATIONS.md) for the current workflow.

# PayPal and Apple Pay setup

The client chooses **$10 Quick Question**, **$15 Detailed Guidance**, **$25 Phone Support**, or **Free Community Support** before submitting.

1. For **PayPal or Apple Pay**, the website opens the question-specific secure checkout after submission. A successful capture marks the CloudKit question **Paid** automatically.
2. Free Community Support skips checkout and requires no payment.
3. Begin paid services after the app shows Paid. No manual payment-link messages or status buttons are used.
4. Issue any approved refund in PayPal. Verified provider webhooks update Refunded or Partially refunded automatically; changing an app label does not issue a refund.

The app stores only the selected amount, provider, status, and checkout URL. Card and bank information stays with PayPal or Apple Pay.

## Cloudflare Worker secrets

Add these secrets to `vet-helpline-development`:

- `PAYPAL_CLIENT_ID` — Live PayPal REST app client ID.
- `PAYPAL_CLIENT_SECRET` — Live PayPal REST app secret.
- `PAYPAL_WEBHOOK_ID` — ID for a webhook pointed at `https://vet-helpline-development.dkjmmz6whh.workers.dev/paypal/webhook`.

Set `PAYPAL_ENVIRONMENT` to `live` after sandbox testing. Subscribe the webhook to `PAYMENT.CAPTURE.COMPLETED`, `PAYMENT.CAPTURE.REFUNDED`, and `PAYMENT.CAPTURE.REVERSED`. Completion webhooks recover a successful capture when the browser closes or the CloudKit update fails. Capture retries reuse an already completed order and never charge it again. Storage failures return a retryable error to PayPal. Enable Apple Pay for the PayPal app and register the Worker checkout domain in PayPal before live Apple Pay testing.

Run `npm test` and `npm run check` in `relay` before deploying. The tests use fictional records and mocked providers; a sandbox buyer approval and capture are still required to verify the merchant integration.

## Checkout regression checks

Checkout must allow `https://applepay.cdn-apple.com` in `script-src`, `frame-src`, and `img-src`; otherwise the Apple Pay payment sheet can show “This content is blocked.” PayPal SDK resources also use PayPal subdomains. Keep the provider sources in the checkout Content Security Policy when changing headers. See [Apple SDK security policy guidance](https://developer.apple.com/documentation/applepayontheweb/loading-the-latest-version-of-apple-pay-js) and [PayPal SDK best practices](https://developer.paypal.com/sdk/js/v5/best-practices/).

Serve the Apple Pay association file directly with HTTP 200 and `Content-Type: application/octet-stream`, without a redirect. The checkout requests the billing postal address and gives visible messages for unavailable devices, merchant validation errors, cancellation, and declined payments.

A verified completed capture returns payment success even if CloudKit synchronization is delayed (HTTP 202 with `statusSyncPending`). The client displays “Payment received” while the verified completion webhook retries the app update. The operator still waits for Paid in the app before providing paid service.

Before release, run the backend and checkout script tests. Then open an unpaid test request on the deployed checkout, verify PayPal/card buttons and the Apple Pay payment sheet, and cancel before authorization. Actual wallet authorization and settlement require a buyer test on a supported device; opening the sheet alone does not prove capture.

After a verified capture, checkout removes payment controls, shows receipt confirmation and the expected reply method, and offers **Ask another question** to start a separate intake. Reopening a paid request shows confirmation with no payment SDK or buttons. The server rejects new orders for paid requests. PetAssist confirmation links back to PetAssist instead.
