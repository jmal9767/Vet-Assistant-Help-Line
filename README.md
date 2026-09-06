# Veterinary Assistant Help Line

One service for **Jahmal Parris / Bay Area Apps LLC**: a public client question website, a private iPhone work inbox, and a small payment-verifying server. Clients contact Jahmal for human-written, general nonmedical education. The iPhone app is for Jahmal only and is not intended for App Store submission.

The source is prepared for configuration and review. A Stripe account alone does not connect it: HTTPS hosting, server secrets, webhook registration, the support mailbox, and a signed installation on Jahmal’s iPhone are still required. Do not open live intake before the acceptance checks in `docs/SOLO_WORKFLOW.md` are complete.

## One service catalog

`VetAssistantHelpLine/Resources/service-catalog.json` is the one source for categories, fifteen starter questions, scope confirmations, response-quality checklist, price, and response deadlines. It is bundled into the private iPhone app and available through authenticated `/api/admin/catalog`. The website’s `/api/catalog` returns only explicitly approved client fields; internal writing goals, research bookmarks and the operator checklist are excluded. Do not create separate catalogs in HTML or Swift.

## Who sees what

| Audience | Available information |
|---|---|
| Clients before purchase | Service description, professional role and limits, categories/examples, price, what is included, response target, refunds, privacy and support |
| A client using their private question link | Their question, published answer and cited sources, clarification, payment/refund status and deadlines |
| Authenticated operator | Internal response goals, research bookmarks, review checklist, service notes, payment references, reply handoff status and inbox controls |
| Private repository/operating guides | Pricing rationale, business strategy, technical setup, security procedures and development decisions |

Client responses are selected by an allowlist at the server, not filtered only in the browser. Adding a new internal catalog or stored-payload field therefore does not expose it automatically. Notes remain private; receipts receive a standard client notice derived from payment/refund status. Only the final published reply content and its citations are shown to that client. The private service guide is available after unlocking the iPhone app. Keep the repository private and never serve its root directory publicly.

The five topics are brushing/grooming preparation, bringing a pet home, enrichment/everyday routines, routine vet-visit preparation, and sitter/household organization. The price is **$9.99 USD** for one topic, a practical answer with relevant sources, and one same-topic clarification. Medical concerns, referrals, scope questions and payment support are outside checkout. A referral-only or otherwise ineligible paid question receives a full refund.

## Code map

| Location | Responsibility |
|---|---|
| `VetAssistantHelpLine/` | SwiftUI operator inbox, Keychain credentials, device unlock, human answer editor, Mail handoff |
| `server/app.py` | Public intake/private receipt API, private operator API, Stripe verification, SQLite state, refunds |
| `server/domain.py` | Catalog validation, conservative extra scope routing, Pacific business-day deadlines |
| `index.html`, `intake.js` | Client category selection, examples, scope confirmations, saved receipt link, Stripe checkout |
| `status.html`, `status.js` | Private payment status, published answer, clarification and cancellation |
| `terms.html`, `privacy.html` | Client-facing policies; update when the catalog or actual deployment changes |
| `docs/PRODUCT_REVIEW.md` | Question/response review, price decision, removed conflicts and remaining launch gates |
| `docs/RESPONSE_TEMPLATES.md` | Human writing standards and category-specific examples; never automatic replies |
| `docs/SOLO_WORKFLOW.md` | Server setup, daily work, email/reconciliation, test-to-live/device checks |
| `docs/LEGAL_SCOPE.md`, `SECURITY.md` | Service boundaries and security operations |

The obsolete client iOS purchase screens, StoreKit product configuration and Apple transaction verifier were removed. They are recoverable from Git history; do not restore them into this architecture. There is no AI SDK, ChatGPT app, second client app, or duplicate payment integration. `sw.js` only retires an old service worker at an existing origin; the current site registers no worker and caches no private pages.

## Local verification

Python 3.12 and Node are used for server/site checks. No Stripe key is needed for the automated tests and they make no real charges.

```sh
python3 -m venv .venv
.venv/bin/python -m pip install --require-hashes -r server/requirements.lock
.venv/bin/python -m unittest discover -s server -p 'test_*.py' -v
.venv/bin/python scripts/check_repository.py
node --check intake.js
node --check status.js
node --check sw.js
```

On a Mac with Xcode 16 or newer, open `VetAssistantHelpLine.xcodeproj` and run the shared `VetAssistantHelpLine` scheme. The iOS workflow builds, tests and analyzes without signing on a simulator. A simulator cannot validate Face ID/passcode, Apple Mail delivery, or a real Apple Pay checkout; those require the physical-device acceptance checks.

Runtime dependencies are pinned and hash-locked in `server/requirements.lock`. Dependabot watches `/server`. Review SDK behavior when updating Stripe, including StripeObject conversion and signature verification, and rerun the payment contract tests.

## Deployment shape

Serve the Flask application at the root of a dedicated HTTPS origin using a production WSGI server and persistent private storage. Do not publish this repository as a static directory or expose its database, source files, environment, or Git metadata. GitHub Pages alone cannot run the payment and inbox APIs. The iPhone stores a separate private device credential, never a Stripe secret. Server configuration and launch steps are in the operating guide.
