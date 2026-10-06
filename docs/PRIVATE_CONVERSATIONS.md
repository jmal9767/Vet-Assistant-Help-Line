# Private Care Line conversations

New written services are Quick Question — Private Message ($10), Detailed Guidance — Private Message ($15), and Free Community Support — Private Message (Free). Phone Support remains $25 and uses the private page to arrange a separate call. PayPal/Apple Pay still pay the same existing business account; this feature does not change payouts or fees.

Clients submit on the care-line website and land on a private conversation page, where paid clients can open checkout. They must bookmark or copy that private link and return to see replies. Messages refresh every 15 seconds while the page is visible. No SMS/email notification or automatic email delivery is provided. The operator opens a question in the app, taps **Reply in Care Line**, types a response, and taps **Send Care Line Reply**. The sender is the business name, not the personal phone/email. Posting a business response marks the question answered; a client follow-up marks it new when CloudKit synchronization succeeds. Message delivery remains durable even if the badge update fails.

Older Email/Text questions retain their original requested service. Their owner can create and share a private conversation before switching communication methods; legacy email composition remains available. New intake does not advertise SMS/email replies. Calls still use the phone carrier and do not mask caller ID. Confirm caller-ID settings before using a personal number.

## Access and storage

Only the registered Care Line iPhone can obtain its reply credential by signing a fresh, replay-protected P-256 device proof. CARELINE_DEVICE_PUBLIC_KEY and CARELINE_OPERATOR_KEY are worker secrets, separate from Visits. The private key stays in the iPhone Secure Enclave/Keychain; no business credential is embedded in app binaries or website source. The public device key is exported to Documents/careline-device-public-key.txt for owner registration.

Each client has a random 32-hex thread reference and separate 64-hex access key. Access remains in the URL fragment and Authorization header, not query strings; no localStorage or conversation caching is used. CloudKit stores the question and conversation reference, never the client access key. Cloudflare Durable Objects store messages and the access key. Each client route checks its own key before looking up question content. Sender labels are chosen on the server; repeated message IDs do not duplicate delivery. Archiving retains the conversation. Permanent deletion erases its access key/messages before deleting CloudKit; repeated deletion safely recovers from CloudKit failure. Deleting CloudKit separately also makes the thread unavailable.

Verification: regression tests cover isolation, replay/tampering, prices, retry-safe delivery, legacy migration, deletion and badge-sync failures; compile the native app and check the private page on a narrow screen before deployment. Live tests use fictional clients only; no real charge is required.

## Shared appearance

The app and care-line web pages use the Bay Area Apps palette: canvas #0e1014, cards #191d24, red #c81e30, gold #f2c65b, and readable white/gray text. The app uses dark appearance consistently, rounded cards and paw-themed service icons. New conversation screens follow those same colors.
