# PayPal, Apple Pay, and Cash App setup

The client chooses a **$10 quick response**, **$20 written support**, **$30 live-text conversation**, or **$35 phone conversation** before submitting.

1. For **PayPal or Apple Pay**, the website opens the question-specific secure checkout after submission. A successful capture marks the CloudKit question **Paid** automatically.
2. For **Cash App**, the selected price and payment method appear in the operator app. Send the Cash App for Business link when needed and mark the question paid only after the payment appears in Cash App.
3. Begin the requested service after confirming payment.
4. Use **Refunded** only after the provider confirms the refund.

The app stores only the selected amount, provider, status, and checkout URL. Card and bank information stays with PayPal, Apple Pay, or Cash App.

## Cloudflare Worker secrets

Add these secrets to `vet-helpline-development`:

- `PAYPAL_CLIENT_ID` — PayPal REST app client ID for the environment in `PAYPAL_ENVIRONMENT`.
- `PAYPAL_CLIENT_SECRET` — matching PayPal REST app secret.
- `PAYPAL_WEBHOOK_ID` — ID for a webhook pointed at `https://vet-helpline-development.dkjmmz6whh.workers.dev/paypal/webhook`.

`PAYPAL_ENVIRONMENT` stays `sandbox` while `CLOUDKIT_ENVIRONMENT` is `development`. The relay refuses live PayPal and Apple Pay checkout in that combination, because a Release, TestFlight, or App Store build reads CloudKit Production and would miss the paid question. After the Production schema is deployed and the operator role is assigned, set both `CLOUDKIT_ENVIRONMENT` and `PAYPAL_ENVIRONMENT` to `production` and `live`, then redeploy.

`relay/payment-worker.js` is a retired Stripe hold-and-capture worker. Do not deploy it. It no longer creates charges or captures a card on a timer. PayPal, Apple Pay, and Cash App in this guide are the only payment path.

Subscribe the webhook to `PAYMENT.CAPTURE.REFUNDED` and `PAYMENT.CAPTURE.REVERSED`. Enable Apple Pay for the PayPal app and register the Worker checkout domain in PayPal before live Apple Pay testing.
