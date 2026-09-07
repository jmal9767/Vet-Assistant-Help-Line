# Payments Setup — pre-authorize, capture on approval (or after 24h)

How money moves:

```
You confirm the price  →  client taps your payment link  →  card AUTHORIZED (held, not charged)
                                                                    │
                 you send the answer with an approval link          │
                                                                    ▼
        client taps "complete payment"  ──── OR ────  24 hours pass with no response
                                └──────────► payment CAPTURED (money reaches your account)
```

The client's money is never taken before they get their answer, and you never
go unpaid because someone ignored the approval link. Card authorizations last
7 days, so the 24-hour auto-capture is comfortably inside the limit.

Everything below is one-time setup, roughly 20–30 minutes.

## 1. Stripe account (~10 min)

1. Create an account at [stripe.com](https://dashboard.stripe.com/register) —
   it needs your legal name, bank account (for payouts), and tax info.
2. In **Developers → API keys**, copy the **Secret key** (`sk_live_…`).
   While testing you can use the test key (`sk_test_…`) and the card number
   `4242 4242 4242 4242`.

Stripe's fee is about 2.9% + 30¢ per charge; payouts land in your bank in ~2 days.

## 2. Deploy the payment Worker (~10 min)

In your Cloudflare dashboard (same account as the question relay):

1. **Workers & Pages → Create Worker**, name it e.g. `vet-helpline-payments`,
   paste in [`relay/payment-worker.js`](../relay/payment-worker.js), deploy.
2. **Storage & Databases → KV → Create namespace** named `PAYMENTS`, then in the
   Worker's **Settings → Bindings** add a KV binding: variable name `PAYMENTS`,
   pick that namespace.
3. **Settings → Variables and Secrets**:

   | Name | Value |
   |------|-------|
   | `STRIPE_SECRET_KEY` | your Stripe secret key (mark as **Secret**) |
   | `OPERATOR_KEY` | a long random password only you know (mark as **Secret**) — generate one with `openssl rand -hex 24` |
   | `SITE_URL` | `https://jmal9767.github.io/Vet-Assistant-Help-Line/` |

4. **Settings → Triggers → Cron Triggers → Add**: `0 * * * *` (hourly).
   This is what auto-captures payments older than 24 hours.

## 3. Daily use (no setup, this is the routine)

Bookmark this on your phone (fill in your own worker URL and operator key):

```
https://vet-helpline-payments.<you>.workers.dev/new?key=<OPERATOR_KEY>&amount=20&desc=Detailed+question
```

Change `amount` and `desc` per request. The page gives you two links:

1. **Payment link** — send it to the client when you confirm the price.
   They pay; the card is authorized but NOT charged.
2. **Approval link** — paste it at the end of your answer:
   *"Happy with the answer? Tap here to complete your payment."*
   - Client taps it → payment completes.
   - Client doesn't → it completes automatically after 24 hours.

## Refunds

If someone is unhappy after auto-capture, refund from the Stripe dashboard
(**Payments → ⋯ → Refund**) — that honors the satisfaction guarantee on the site.

## Test before going live

Use the `sk_test_…` key first: create a $1 payment, pay with card
`4242 4242 4242 4242`, tap the approval link, and confirm the payment shows
as succeeded in the Stripe test dashboard. Then swap in the live key.
