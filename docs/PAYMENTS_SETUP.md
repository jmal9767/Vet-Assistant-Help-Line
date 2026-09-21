# PayPal, Apple Pay, and Cash App setup

The client chooses a **$10 quick response**, **$20 written support**, **$30 live-text conversation**, or **$35 phone conversation** before submitting.

1. For **PayPal or Apple Pay**, the website opens the question-specific secure checkout after submission. A successful capture marks the CloudKit question **Paid** automatically.
2. For **Cash App**, the selected price and payment method appear in the operator app. Send the Cash App for Business link when needed and mark the question paid only after the payment appears in Cash App.
3. Begin the requested service after confirming payment.
4. Use **Refunded** only after the provider confirms the refund.

The app stores only the selected amount, provider, status, and checkout URL. Card and bank information stays with PayPal, Apple Pay, or Cash App.

## Cloudflare Worker secrets

Add these secrets to `vet-helpline-development`:

- `PAYPAL_CLIENT_ID` — Live PayPal REST app client ID.
- `PAYPAL_CLIENT_SECRET` — Live PayPal REST app secret.
- `PAYPAL_WEBHOOK_ID` — ID for a webhook pointed at `https://vet-helpline-development.dkjmmz6whh.workers.dev/paypal/webhook`.

Set `PAYPAL_ENVIRONMENT` to `live` after sandbox testing. Subscribe the webhook to `PAYMENT.CAPTURE.REFUNDED` and `PAYMENT.CAPTURE.REVERSED`. Enable Apple Pay for the PayPal app and register the Worker checkout domain in PayPal before live Apple Pay testing.
