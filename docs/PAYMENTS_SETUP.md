# PayPal, Apple Pay, and Cash App setup

Submitting a question never charges the client.

1. Review the question and estimate the time needed.
2. Open the question in the operator app.
3. Choose a **$10 quick response**, **$20 written support**, **$35 phone/live-text conversation**, complimentary service, or no-charge referral.
4. For **PayPal or Apple Pay**, send the question-specific checkout link. A successful capture marks the CloudKit question **Paid** automatically.
5. For **Cash App**, send your Cash App for Business link and mark the question paid only after the payment appears in Cash App.
6. Use **Refunded** only after the provider confirms the refund.

The app stores only the selected amount, provider, status, and checkout URL. Card and bank information stays with PayPal, Apple Pay, or Cash App.

## Cloudflare Worker secrets

Add these secrets to `vet-helpline-development`:

- `PAYPAL_CLIENT_ID` — Live PayPal REST app client ID.
- `PAYPAL_CLIENT_SECRET` — Live PayPal REST app secret.
- `PAYPAL_WEBHOOK_ID` — ID for a webhook pointed at `https://vet-helpline-development.dkjmmz6whh.workers.dev/paypal/webhook`.

Set `PAYPAL_ENVIRONMENT` to `live` after sandbox testing. Subscribe the webhook to `PAYMENT.CAPTURE.REFUNDED` and `PAYMENT.CAPTURE.REVERSED`. Enable Apple Pay for the PayPal app and register the Worker checkout domain in PayPal before live Apple Pay testing.
