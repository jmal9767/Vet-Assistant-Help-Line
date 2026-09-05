# Solo Operator Workflow

This is the v1 operating procedure for the paid email service defined in
[LEGAL_SCOPE.md](./LEGAL_SCOPE.md). Customer messages must use the approved
patterns and mandatory scope checklist in
[RESPONSE_TEMPLATES.md](./RESPONSE_TEMPLATES.md).

## V1 operating facts

- The app has no account system, submission server, remote capacity switch, or
  email-delivery confirmation. The operator keeps a separate local SQLite
  redemption ledger containing only HMAC-SHA-256 transaction and submission
  digests, environment, and redemption timestamps.
- One Apple consumable purchase covers one prepared question email. The app holds
  a locally verified StoreKit transaction unfinished until the email handoff is
  resolved. Cancelling the fallback before copying the complete email makes it
  reusable. Once Apple Mail displays the complete body, a saved, cancelled,
  failed, or unknown result—or a copied/opened fallback—locks it until the customer
  confirms sent or deleted without sending.
- The app records transaction-ID email-handoff and delivery markers and finishes
  the transaction when Apple Mail reports `.sent`, or when the customer explicitly
  confirms sending through the fallback flow. `.sent` may mean queued; it does not
  prove inbox delivery. A marker is removed only after a positive finish or an
  explicit deleted-without-sending decision; an absent account-specific StoreKit
  scan is not proof that it is safe to remove.
- Each prepared email includes Apple's signed transaction JWS and a matching
  StoreKit `appAccountToken`. An initial message is a paid submission only after
  the operator verifier validates the emailed Production JWS, obtains and
  validates Apple's current signed transaction information, and atomically
  inserts its keyed transaction and submission digests once. A raw or
  customer-edited transaction number is never trusted.
- After finishing, the app cannot restore an in-app credit. Every valid paid
  initial submission that is outside scope receives exactly one replacement
  opportunity without another purchase. It must come from the original sender in
  the canonical thread by the exact disclosed deadline. Definitively invalid
  proof, fraud, or abuse does not create a valid paid initial or a replacement
  right. The operator tracks the right in the mailbox, not in the app.
- Emergency redirects and administrative, privacy, provider-directory, and
  purchase-support replies are free.
- A paid initial or replacement submission normally receives one human review
  result—either an eligible educational answer or a scope/referral response—by
  5:00 p.m. Pacific Time on the second business day after it actually reaches
  `info@bayareaapps.com`. This is a target, not a guarantee. There are no calls,
  consultations, live chat, file reviews, or medical answers.

These limitations are product constraints, not implementation details to hide.
They must be disclosed before purchase.

## Pre-launch requirements

Do not enable the paid product until all items are complete:

1. Confirm with California counsel that the actual operator, business entity,
   service copy, age gate, and App Store distribution plan fit the narrow scope in
   [LEGAL_SCOPE.md](./LEGAL_SCOPE.md). Verify every public claim about the
   operator's title and credentials.
2. Complete and test every control in **Mailbox hardening** below before using
   `info@bayareaapps.com` for a purchase or customer question.
3. Configure the Apple product as a consumable named **One Education Question
   Email**, with the exact StoreKit product display description **One nonmedical education question email.**
   Show StoreKit's localized `Product.displayPrice`; never hard-code a price. Put
   the response target, email-handoff, scope, replacement, refund, and emergency
   terms in adjacent purchase UI and the App Store listing rather than lengthening
   or contradicting that short field.
4. Require the free safety, scope, purchase/email, and age confirmations before
   any purchase control. None may be preselected.
5. Limit the form and prepared email to one plain-text, nonmedical topic, a
   StoreKit-bound submission reference, Apple purchase reference and signed JWS,
   and reply address. Do not ask for a pet name, demographics, symptoms, records,
   images, or attachments.
6. Configure and test the verifier in [`operator/README.md`](../operator/README.md)
   with Apple's current root certificates, the numeric Production App Apple ID,
   an In-App Purchase API private key, key ID and issuer ID, a separate protected
   HMAC key, an encrypted production ledger with secure backups, and a wholly
   separate Sandbox ledger and key. Never accept a paid answer if signature
   verification, Apple's current-transaction lookup, or the ledger is unavailable.
7. Establish and test an operator-controlled App Store procedure that makes new
   purchases unavailable. Measure its propagation delay and build that delay into
   the capacity threshold. If purchases cannot be stopped safely, keep the paid
   product unavailable until remote capacity control is added.
8. Configure only the fixed, deterministic receipt acknowledgment in the service
   mailbox. Send at most one receipt for each eligible human-origin message. Do not
   use an AI autoresponder, classifier, summarizer, or generator. Suppress the
   service's own sender, automated/bulk/list mail, delivery-status notices and
   bounces, and messages already marked as acknowledged; test these loop controls
   before enabling the rule.
9. Create mailbox labels: `NEW`, `PAYMENT-HOLD`, `PAYMENT-REJECTED`,
   `PAYMENT-REPLAY`, `EMERGENCY-REFERRED`, `SCOPE-REFERRED`,
   `REPLACEMENT-OFFERED`, `REPLACEMENT-IN-REVIEW`, `REPLACEMENT-CLOSED`,
   `READY-TO-WRITE`, `ANSWERED`, `SUPPORT`, `DELETE-REQUEST`, and `PURGE`.
10. Test locally verified and unverified purchases, pending purchase, purchase
   cancel, Apple Mail saved/cancelled/failed/unknown results, Mail `.sent`, fallback
   cancellation before copy, fallback confirmation after copy/open, app termination
   between email-handoff journaling and `finish()`, unfinished-transaction recovery,
   missing email, exact resend, and duplicate-purchase support.
11. Publish privacy and retention terms that match the actual app, mailbox, Apple,
    and email-provider behavior. Do not claim v1 has a backend, account, server
    remote verification, instant stop-sale control, or guaranteed delivery.

## StoreKit and Mail lifecycle

| Event | Required v1 behavior |
|---|---|
| Verified unfinished transaction | Expose one reusable local submission credit; deduplicate by StoreKit transaction ID. |
| Purchase pending or unverified | Grant nothing and do not prepare a sendable email. |
| Fallback dismissed before the complete email is copied or another app is opened | Clear the handoff marker; do not call `finish()`; keep the verified unfinished transaction reusable. |
| Composer saved, cancelled, failed, or returned an unknown result after the complete body was displayed | Keep the transaction unfinished but lock duplicate preparation until the customer explicitly confirms sent or deleted without sending. |
| Apple Mail reports `.sent` | Persist the transaction ID to the local email-handoff journal, call `finish()`, then clear the journal and local credit. |
| Complete fallback email copied or another mail app opened | Keep the transaction unfinished but lock duplicate preparation until the customer explicitly confirms sent or deleted without sending. Copying or opening alone is not submission. |
| Customer explicitly confirms fallback send | Persist the transaction ID to the local email-handoff journal, call `finish()`, then clear the journal and local credit. |
| Customer confirms any displayed/copied unresolved email was deleted without sending | Clear the unresolved-handoff marker; do not call `finish()`; make the same unfinished credit reusable. |
| App relaunch finds a journaled unfinished transaction | Finish that transaction without granting it again, then clear the journal. |
| App relaunch does not find a journaled ID in the current account's unfinished scan | Retain the marker. An absent account-specific scan is not positive proof of finish; the marker may remain until the transaction reappears and finishes, the handoff is explicitly resolved where applicable, or app data is removed. |

The local email-handoff journal is crash protection, not inbox-delivery evidence,
a customer account, or the operator redemption ledger.
Never finish merely because the email was prepared, copied, opened, saved as a
draft, or the purchase succeeded. Keep any portable or uncertain handoff locked
against duplicate preparation until the customer explicitly resolves it. After
`.sent` or explicit sent confirmation, describe the in-app transaction as
finished and unavailable for reuse; after an explicit deleted-without-sending
confirmation, unlock the same unfinished credit.

The response clock starts at actual receipt in the operator inbox, not at Mail
handoff, acknowledgment, payment verification, or the start of a work shift. The
first business day after actual receipt is day one; the human review result is due
by 5:00 p.m. Pacific Time on day two. Business days are Monday through Friday,
excluding U.S. federal holidays. There is no 5:00 p.m. receipt cutoff or rollover:
an email received at any time on Monday ordinarily has Tuesday as day one and
Wednesday as day two; a weekend or holiday receipt ordinarily has the next
business day as day one. This is a target, not a guarantee. A replacement gets a
new clock based on its own actual inbox receipt.

## Mailbox hardening

- Use `info@bayareaapps.com` only for this service and access it only from a
  dedicated, encrypted operator device or isolated encrypted profile. Require
  multi-factor authentication, unique credentials, controlled recovery, and
  least-privilege mailbox and App Store access. Alert on new forwarding rules,
  recovery changes, and suspicious sign-ins.
- Read customer messages in plain-text view. Disable remote-image loading, link
  previews, and automatic attachment download or preview. Never click or open a
  customer-supplied link, even when its displayed text appears familiar. Navigate
  independently to known Apple and official-source domains.
- Configure SPF, DKIM, DMARC, and TLS delivery for `bayareaapps.com`. Send and
  receive controlled test messages through every legitimate service that sends
  for the domain, then inspect the raw `Authentication-Results` headers and
  confirm SPF, DKIM, and DMARC alignment. Stage SPF hard-fail and DMARC reject
  only after all legitimate senders and forwarding behavior have been validated;
  monitor reports during each stage.
- Assess and document MTA-STS and TLS-RPT, including how reports are reviewed and
  how a delivery failure is escalated. Re-test these controls after any provider,
  DNS, forwarding, or recovery change.

## Mailbox review order

Review `NEW` at the start of each business day and at least once again before
close. The mailbox is not continuously monitored and must never be described as
an emergency channel.

For each new message:

1. Without opening or previewing any attachment, read the subject and plain-text
   body for symptoms, injury, exposure, poisoning, distress, rapid change,
   emergency language, or a question about whether care can wait. If any appears,
   send a clean emergency redirect immediately, without quoted customer content
   and without waiting for payment verification. Do not assess urgency.
2. Before treating the message as a new purchase, check whether it came from the
   original sender in the canonical thread labeled `REPLACEMENT-OFFERED` and
   arrived no later than its exact replacement deadline. Classify it without
   consuming the replacement right:

   - thanks, administrative, privacy, purchase-support, provider/cost-resource,
     autoresponse, and safety-only messages are free and leave
     `REPLACEMENT-OFFERED` unchanged;
   - if it is genuinely ambiguous whether the customer is trying to submit the
     replacement question, ask only for clarification of that intent, without
     requesting animal or health details, and leave `REPLACEMENT-OFFERED`
     unchanged; and
   - if it clearly attempts to exercise the replacement by submitting a question,
     atomically remove `REPLACEMENT-OFFERED`, add `REPLACEMENT-IN-REVIEW`, and
     record its actual inbox-receipt timestamp before evaluating scope. The first
     such attempt in chronological inbox order is the one authorized replacement
     and consumes the right even if the question is later found ineligible.

   Perform that transition as one mailbox label action under a single-operator
   processing lock. Do not evaluate another message in the thread until the
   transition and receipt timestamp are recorded.

   Do **not** rerun or redeem the Apple proof for an authorized replacement. A new
   thread, changed sender, late reply, `REPLACEMENT-IN-REVIEW` thread, or
   `REPLACEMENT-CLOSED` thread is not another authorized replacement. A later
   message cannot revise or replace the already submitted attempt.
3. For a message that purports to be an initial paid submission, pass only the
   full emailed Apple-signed JWS to the production verifier described in
   [`operator/README.md`](../operator/README.md). The verifier must
   signature-verify that emailed JWS, derive the signed transaction ID and signed
   `appAccountToken` from it, query Apple using that signed transaction ID,
   signature-verify Apple's current JWS, compare all required fields, reject a
   current revocation, and atomically insert the keyed transaction and submission
   digests. Transaction, submission, environment, or token text elsewhere in the
   email is display/support information and is never a verifier input or proof.
   Free safety, administrative, privacy, provider/cost-resource, and
   purchase-support messages need no purchase proof.
4. Apply exactly one verifier outcome:

   - `ACCEPTED` (exit 0) means this is a valid, newly redeemed initial submission.
   - `UNAVAILABLE` (exit 4) is an operational failure, not a payment verdict. Add
     `PAYMENT-HOLD`; do not accept, reject, answer, refer as the paid result, or
     redeem manually. Follow **Payment-verification hold** below. A hold does not
     restart the response clock.
   - `REJECTED` (exit 2) is a definitive invalid-proof, field-mismatch,
     non-Production, or revocation result. Add `PAYMENT-REJECTED`; do not redeem it
     or create a replacement right. Send only applicable free safety or
     purchase-support information and preserve the audit record required for the
     documented fraud/dispute period.
   - `REPLAYED` (exit 3) means the signed identifiers already exist in the ledger.
     Add `PAYMENT-REPLAY`, locate the canonical mailbox thread, and consolidate an
     exact technical resend into the original submission. It is not a new paid
     submission. A changed question is not accepted through replay handling; it
     can qualify only through the open-replacement classification in step 2.

   Never infer a verdict from an exception, customer-edited field, or raw
   transaction number.
5. If an unexpected attachment exists, do not open, preview, download, forward,
   or intentionally process it. After completing any required thread and proof
   checks in steps 2–4 using only the plain-text fields, send the attachment
   referral unless step 1 already sent the emergency redirect; never send a
   duplicate clinical redirect. If the verifier returned `UNAVAILABLE`, first use
   the proof-only hold-file procedure below. Then permanently delete the original
   message and attachment from the active mailbox and Trash. Do not apply a paid
   replacement status until the hold reaches a definitive result; an `ACCEPTED`
   initial with an attachment then receives its guaranteed replacement offer in
   the clean canonical reply thread.
6. For any other prohibited medical, safety, product, medication, diet, dose,
   treatment, prognosis, record, test, image, or individual-animal request, send
   the matching referral unless the emergency redirect was already sent. Refer
   the entire mixed submission and add no medical commentary.
7. For a nonmedical but unclear or multiple-question submission, use the
   one-question response. Do not solicit health details.
8. After any ineligible submission, apply exactly one status outcome. For a
   valid initial submission, guarantee exactly one replacement: append the
   initial replacement paragraph to an unsent referral or send it as a separate
   same-thread follow-up after an immediate emergency redirect. Compute the 90th
   calendar day from the timestamp when that replacement-offer email is sent,
   state the exact 11:59 p.m. Pacific Time deadline in the message, add
   `REPLACEMENT-OFFERED`, and record the offer timestamp and deadline. For the
   authorized replacement in `REPLACEMENT-IN-REVIEW`, use the final replacement
   paragraph, atomically replace that label with `REPLACEMENT-CLOSED`, and offer
   no second replacement. With no valid initial submission or authorized
   replacement, send no replacement paragraph.
9. Accept an eligible question only when it is either the verified initial
   submission from step 3 or the authorized replacement from step 2. Add
   `READY-TO-WRITE`, research current authoritative primary sources, personally
   write the answer without generative AI, and complete every mandatory pre-send
   checklist item.
10. Send the review result from `info@bayareaapps.com`. For an eligible answer,
    add `ANSWERED`; for a completed referral, add `SCOPE-REFERRED`. Close the paid
    review unless a valid initial referral has just opened
    `REPLACEMENT-OFFERED`. Record the applicable closure and purge dates under the
    retention rules below. Sending the result does not consume or restore an
    Apple credit; that lifecycle already ended on question-email submission.

An exact resend caused by a Mail handoff or delivery problem is the same initial
submission and does not use the one replacement. Check references and content,
remove duplicates, and keep one canonical thread.

When uncertain, refer, preserve any still-unused replacement right, record the
scope issue without copying customer content elsewhere, and obtain qualified
California legal advice before changing the scope.

## Payment-verification hold

For every `UNAVAILABLE`/exit-4 result:

1. Add `PAYMENT-HOLD` and preserve the original message and exact signed JWS,
   except when the message has an unexpected attachment and must use the
   proof-only hold-file procedure below. Do not edit identifiers, bypass the
   verifier, manipulate the ledger, infer a payment decision, or perform scope
   review as the paid result.
2. Send the verification-delay template without asking the customer to repurchase
   or provide new proof. Record the hold time and the verifier's non-customer
   diagnostic category; never copy the question or JWS into a ticket or log.
3. Check the trusted time, Apple availability, network, current root certificates,
   API credential access, dependency health, encrypted-disk state, ledger and
   parent-directory permissions, HMAC key, and Production-ledger metadata. Correct
   only the operational fault; never reset or replace the ledger to force a new
   result.
4. Retry the exact same JWS. On `ACCEPTED`, remove `PAYMENT-HOLD` and continue the
   initial-submission review. On definitive `REJECTED`, replace it with
   `PAYMENT-REJECTED` and provide only free support. On `REPLAYED`, replace it with
   `PAYMENT-REPLAY` and reconcile the canonical thread. A repeated `UNAVAILABLE`
   remains on hold. Immediately delete any temporary hold file after a definitive
   verdict; remove it from temporary storage and Trash and retain only the normal
   time-bounded audit record.
5. Begin the tested stop-sale procedure immediately when `UNAVAILABLE` occurs and
   keep new sales paused while the hold is unresolved. Resume only after the same
   proof reaches a definitive result, the fault is corrected, verification and a
   controlled Production test are healthy, and the capacity-resume conditions
   below are met. Continue free emergency, privacy, and purchase support and honor
   existing same-thread replacement rights while sales are paused.

The original actual inbox-receipt timestamp remains the response-clock anchor.
If the target may be missed, notify the customer of the operational delay without
calling it a payment rejection, promising a deadline, or requesting a repurchase.

### Proof-only hold file for an unexpected attachment

The pre-launch test must establish this path before paid sales begin. If a message
with an unexpected attachment returns `UNAVAILABLE`:

1. Generate a random, non-customer hold reference. Without opening or processing
   the attachment, copy only the exact JWS string from the plain-text body into a
   newly created file named with that hold reference. The file must contain no
   question, email address, subject, display reference, attachment, or other
   message content.
2. Create it exclusively, without following symlinks, at mode `0600` inside a
   dedicated mode-`0700` directory on the encrypted operator volume. Exclude that
   directory from backup, cloud sync, indexing, and previews. Never put the JWS
   contents in a command argument or shell history; use only the verifier's file
   input.
3. Put the random hold reference in the clean verification-delay reply so its Sent
   copy connects the customer thread to the local proof file. Send any required
   emergency or attachment referral without quoting the original, then
   permanently delete the original message and attachment from the active mailbox,
   Trash, downloads, and provider-controlled recovery folders where configurable.
4. Retry verification from that exact file. Do not add command-line identifiers or
   reconstruct the JWS. After `ACCEPTED`, `REJECTED`, or `REPLAYED`, immediately
   delete the file as required in step 4 above. A repeated `UNAVAILABLE` keeps the
   file only for the active hold and keeps sales paused.

## Replacement-window control

- Every valid paid initial that is outside scope receives exactly one replacement
  right. A proof that is definitively rejected, fraudulent, or abusive does not
  establish a valid paid initial and creates no right.
- The replacement must come from the same original sender, as a reply in the
  canonical thread, and actually reach the inbox by 11:59 p.m. Pacific Time on
  the 90th calendar day after the replacement-offer email is sent. The offer must
  state the computed calendar date, not merely “within 90 days.” Compute it by
  taking the offer's Pacific calendar date and adding 90 calendar days; do not use
  a 2,160-hour duration across daylight-saving changes.
- Free thanks, administrative, privacy, purchase-support, provider/cost-resource,
  autoresponse, and safety-only messages do not consume the right. Clarify genuine
  ambiguity without consumption. A clear attempt to submit the replacement
  question consumes it at the atomic `REPLACEMENT-OFFERED` to
  `REPLACEMENT-IN-REVIEW` transition, before scope is decided.
- A replacement receives its own human review result—eligible answer or
  scope/referral—under a new two-business-day target based on its actual inbox
  receipt. If it is ineligible, state that no second replacement is offered,
  provide the Apple refund-review path, add `REPLACEMENT-CLOSED`, and close it.
- If no replacement arrives by the exact deadline, add `REPLACEMENT-CLOSED` and
  purge the thread under the retention schedule. A later message is not silently
  treated as paid; use the expired-window paragraph in
  [RESPONSE_TEMPLATES.md](./RESPONSE_TEMPLATES.md). Do not tell the customer to
  repurchase while a dispute is open.

## Capacity pause without a backend

V1 cannot count verified-but-unsent credits on customer devices and cannot stop
purchases remotely in real time. App Store reporting and product-availability
changes may be delayed. Therefore the operator must keep a conservative workload
buffer and pause early.

Before launch, document `C`, the maximum number of paid human review results the
operator can safely complete per business day without AI, including the research
and writing required for eligible answers. Begin the tested stop-sale procedure
immediately when any condition is true:

- the deduplicated number of unresolved threads across `NEW`, `PAYMENT-HOLD`,
  `READY-TO-WRITE`, and `REPLACEMENT-IN-REVIEW` reaches `C`;
- the oldest unresolved paid thread has reached one business day;
- the operator cannot reserve the next two business days for the current queue,
  open replacement rights, and a buffer for already purchased but unsent emails;
- a planned absence, illness, Mail or StoreKit problem, security concern, privacy
  incident, or source-review problem could affect safe or timely service; or
- the operator cannot personally review and write every substantive reply.

Use the tested App Store procedure to make the paid product unavailable and
confirm the result from a production device. Because propagation is not instant,
continue checking for late purchases and incoming emails. Keep free safety
resources, `info@bayareaapps.com` support, privacy requests, and existing
same-thread replacements available. Honor already purchased submissions; if the
published target cannot be met, notify the customer and offer the Apple
refund-review path without promising approval.

Resume only when the inbox is current, systems are healthy, no absence or incident
is active, the next two business days have documented capacity, and the stop-sale
procedure still works. Add a real remote capacity gate before scaling beyond a
manually manageable volume.

## Wind-down without expiring purchases

A locally verified StoreKit credit that the app has not marked sent does not
expire. This app state is separate from operator-ledger redemption, which happens
only when the verifier returns `ACCEPTED` for an initial email. To discontinue the
paid service, first make the product unavailable and confirm from a production
device that no new purchase can begin. Keep the supported app build, service
mailbox, Apple verifier credentials, protected ledger and HMAC key, and operator
capacity available while device credits not marked sent, signed proofs awaiting
reconciliation, payment holds, submissions, and open replacement windows are
resolved. Continue to honor each valid outstanding right, or help the customer
pursue Apple's refund process when fulfillment is no longer possible.

Because v1 cannot enumerate purchased-but-unsent transactions on customer
devices, use a documented conservative waiting period informed by App Store
reporting and support volume. Do not declare the paid service ended, delete the
ledger, retire verification keys, or close the mailbox until counsel confirms the
remaining obligations are resolved. A wind-down never shortens an already-open
90-day replacement window.

## Purchase, delivery, and refund support

Handle support without implying server capabilities:

1. Ask only for the submission reference and Apple purchase reference already
   shown in the prepared email. Never request payment-card data, an Apple Account
   password, a verification code, government ID, or an unnecessary screenshot.
2. If no email was sent or confirmed, ask the customer to reopen the app so
   StoreKit can recover a verified unfinished transaction. Tell them not to buy
   again while it is unresolved.
3. If Mail reported `.sent` but nothing reached the inbox, explain that `.sent`
   may mean queued. Ask the customer to check Outbox and Sent and resend or forward
   the exact prepared message to `info@bayareaapps.com`. Treat this as the original
   submission, not a replacement.
4. If the customer confirmed fallback sending but did not actually send, v1
   cannot restore the finished in-app credit. Ask for an exact resend of the
   prepared email containing the full Apple-signed JWS and run the normal verifier;
   never accept displayed references alone. Do not require another purchase.
5. If a valid paid initial was ineligible, honor exactly one replacement under the
   original-sender, canonical-thread, and exact-deadline rules above. Do not state
   that the app credit was restored.
6. Direct App Store charge and refund requests to
   [reportaproblem.apple.com](https://reportaproblem.apple.com/). Apple decides
   refund eligibility; do not promise approval or issue an off-platform substitute
   payment.
7. Escalate unverified or missing unfinished transactions, repeated StoreKit
   failures, apparent duplicate charges, or refund-status questions to Apple
   Developer Support as appropriate. Pause new purchases if other customers may
   be affected.

## Privacy, retention, and deletion

### Data locations and minimization

Before send, the draft remains in the app. Opening a composer shares the prepared
content with the device's mail service even if the customer later cancels. The
fallback clipboard item is local to the device, expires after 10 minutes, and is
cleared on confirmation or cancellation when still present. V1 has no Bay Area
Apps submission database. On device, the app stores a pending purchase token and
date; unresolved-handoff and recorded-delivery transaction-ID markers; and a last
completed transaction ID that remains readable for 90 days and is removed on the
next app launch after expiry. It does not store the question in those records. A
marker clears only after the relevant positive finish or explicit handoff
resolution and may otherwise remain until app data is removed. These records
describe app purchase and handoff decisions, not inbox delivery. Apple retains its
own transaction records.

After send, the customer's and operator's email providers process and store the
message under their own terms. The prepared message contains the Apple-signed JWS,
which can include transaction, product, price, currency, storefront, environment,
purchase-time, and app-account-token metadata. Bay Area Apps should keep only the
reply address, submission and Apple purchase proof, eligible question, answer, and
minimum support correspondence in the service mailbox. The redemption ledger
stores only HMAC-SHA-256 digests of verified transaction and submission
references, the environment, and a redemption timestamp—never email addresses,
JWS values, or question content. Do not copy content into personal accounts,
analytics, source control, or another database. Do not intentionally submit it to
generative AI or use it for advertising, marketing, or model training.

The sole proof-storage exception is an active `PAYMENT-HOLD` on a message with an
unexpected attachment: the operator may temporarily store only the exact JWS in
the encrypted mode-`0600` proof-only file described above. It uses a random hold
reference, contains no question or other message content, is excluded from sync
and backup, and is deleted immediately after a definitive verifier result. It is
not a customer-content database or a substitute for the redemption ledger.

### Retention and weekly purge

- When an initial eligible answer is sent, or when a final scope/referral response
  closes a submission with no open replacement right, record that sent timestamp
  as `closed_at` and set `purge_at` to 90 calendar days later. Delete
  operator-controlled question, answer, and ordinary support content at
  `purge_at`.
- For a valid initial outside-scope result, do not use the referral timestamp as
  the retention closure. Record `replacement_offered_at` when the offer email is
  sent and `replacement_deadline` as 11:59 p.m. Pacific Time on its 90th calendar
  day. Retain the canonical `REPLACEMENT-OFFERED` thread only through that open
  window. If no replacement arrives, add `REPLACEMENT-CLOSED`, record the deadline
  as `closed_at`, set `purge_at` to 90 calendar days later, and delete the
  operator-controlled thread content at `purge_at`.
- If a replacement arrives on time, retain the canonical thread through that
  replacement's final answer or scope/referral response; record that response as
  `closed_at` and set `purge_at` to 90 calendar days later. The same rule applies
  after an intent-clarification exchange once a clear replacement attempt is
  submitted. No response or label transition shortens the open deadline before
  an attempt is consumed.
- For a free emergency, safety, administrative, privacy, purchase-support,
  provider/cost-resource, or autoresponse message with no paid right, record the
  final reply as `closed_at`—or actual receipt when no reply is warranted—and set
  `purge_at` to 90 calendar days later. Delete its operator-controlled message and
  ordinary support content then, unless an unexpected attachment or deletion
  request requires earlier removal.
- For a definitive `REJECTED` invalid-proof result, first apply the immediate
  unexpected-attachment rule if applicable. Otherwise, record the final free
  support response as `closed_at` and set `purge_at` to 90 calendar days later.
  Delete the message, JWS, and ordinary support content then. Retain a separate
  minimal fraud, security, or transaction-dispute record longer only under the
  documented, time-bounded exception below; do not retain question content merely
  because proof was rejected.
- Keep a `PAYMENT-HOLD` message only while verification is actively unresolved.
  When a definitive result arrives, apply the applicable paid-thread, dispute, or
  invalid-proof retention rule and record its closure and purge dates.
- An unexpected attachment: after any required proof-only extraction for an
  active `PAYMENT-HOLD` and after sending the clean safety/referral response,
  immediately delete the original message and attachment from Inbox, Trash, local
  downloads, provider recovery where configurable, and any operator-controlled
  export. Never intentionally open it. The proof-only temporary JWS file follows
  the hold procedure and is deleted immediately after a definitive verdict.
- A security, fraud, accounting, transaction-dispute, or legal record may be kept
  longer only for a documented purpose and documented expiry, separated from
  question content where feasible.
- Replay-prevention hashes in the redemption ledger are kept for the life of the
  paid service. Record a service-end date only after new sales have stopped and
  device credits not marked sent, signed proofs awaiting reconciliation, payment
  holds, open submissions, disputes, and replacement windows have been honored or
  otherwise resolved. Only then is the service truly ended. Delete the hashes
  from the primary ledger and every operator-controlled backup, replica, and export
  within 90 days after that recorded date unless a documented legal, security,
  dispute, fraud, or accounting need requires a defined longer period. Verify those
  deletions, then destroy every operator-controlled copy and backup of the retired
  HMAC key. Provider-managed backup media may age out only on the limited
  contractual schedule disclosed in the privacy policy. Losing or rolling back the
  ledger before service end can permit a purchase proof to be reused; keep
  encrypted backups and pause paid acceptance until loss is reconciled.

Every Friday, review `PURGE` and replacement-expiry dates, delete due content from
Inbox, Sent, drafts, Trash, downloads, and operator-controlled exports, and record
only the nonidentifying completion date and category. Email providers, Apple, the
customer's device, and the customer's sent-mail copy have their own retention and
are not controlled by Bay Area Apps; say so in the privacy policy.

### Deletion-request workflow

1. Accept a request at `info@bayareaapps.com` and assign a request reference.
2. Verify control through a reply from the customer email address already
   associated with the thread plus its submission or Apple purchase reference.
   Do not collect government ID, payment information, passwords, or codes.
3. Search Inbox, Sent, drafts, Trash, downloads, operator-controlled exports, and
   related support mail for those existing identifiers.
4. Delete or de-identify data controlled by Bay Area Apps. Retain limited data
   only for a documented active legal, security, fraud, accounting, or
   transaction-dispute purpose and record its expiry.
5. Complete the request within 30 calendar days. Confirm completion or explain
   what limited data remains, why, and when it will be deleted. Explain that
   Apple, email providers, the customer's device, and customer-held copies are
   outside Bay Area Apps' control.
6. If an unused replacement opportunity exists, tell the customer before deletion
   that removing the original thread will prevent manual same-thread verification.
   Do not delay deletion if the customer confirms they want it completed.

## Weekly control review

Once each week:

- reconcile the production Mail/StoreKit behavior against the tested lifecycle;
- confirm capacity `C`, the stop-sale procedure, and the workload buffer;
- sample answers against the scope checklist and verify their source links;
- test the free safety screen, product disclosures, receipt rule, and support link;
- purge expired threads and complete deletion requests;
- review access, forwarding rules, failed sign-ins, and device status;
- confirm plain-text view, remote-content and attachment blocking, SPF/DKIM/DMARC
  alignment reports, and the documented MTA-STS/TLS-RPT status; and
- record policy, StoreKit, source, distribution, or legal changes for human review
  before deployment.

## Apple implementation references

- [StoreKit: finishing a transaction](https://developer.apple.com/documentation/storekit/finishing-a-transaction)
- [StoreKit: unfinished transactions](https://developer.apple.com/documentation/storekit/transaction/unfinished)
- [StoreKit: transaction updates](https://developer.apple.com/documentation/storekit/transaction/updates)
- [App Store Server API: Get Transaction Info](https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info)
- [Apple App Store Server Library for Python](https://github.com/apple/app-store-server-library-python)
- [MessageUI: `MFMailComposeResult`](https://developer.apple.com/documentation/messageui/mfmailcomposeresult)
