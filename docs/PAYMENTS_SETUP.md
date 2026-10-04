# PayPal and Apple Pay setup

The client chooses **$5 Quick Question**, **$10 Detailed Guidance**, **$20 Phone Support**, or **Free Community Support** before submitting.

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
