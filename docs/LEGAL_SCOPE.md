# Legal Scope — Paid Pet-Care Education

> Operational guardrails, not legal advice. This document adopts a deliberately
> narrow California model. California counsel should review the actual app,
> operator status, entity, disclosures, and distribution plan before launch and
> after any service change.

This document defines what the service may sell and answer. Use
[RESPONSE_TEMPLATES.md](./RESPONSE_TEMPLATES.md) for customer-facing language and
[SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md) for mail, capacity, privacy, and support
operations.

## Approved service model

The only paid service is **one general, nonmedical pet-care education question by
email**:

1. The customer completes a free safety-and-scope screen before any Apple
   purchase control appears.
2. The customer buys one consumable question-submission credit through Apple
   In-App Purchase.
3. The app prepares one plain-text email to `info@bayareaapps.com` for the
   customer to review and send.
4. A human veterinary assistant reviews the email and normally sends one review
   result—either an eligible educational answer or a scope/referral response—by
   5:00 p.m. Pacific Time on the second business day after the email actually
   reaches the service inbox.

There are no consultations, appointments, phone or video calls, text or direct
messages, live chat, medical follow-up, or AI-generated customer answers. The
operator must not use generative AI to ingest, classify, summarize, draft,
rewrite, translate, select, or send a customer question or reply.

“Normally” is a service target, not an emergency-response promise or guaranteed
deadline. A business day is Monday through Friday, excluding U.S. federal
holidays, measured in Pacific Time. The response clock starts at actual inbox
receipt, not when Apple Mail reports sent, payment is verified, or review begins.
The first business day after actual receipt is day one, and the result is due by
5:00 p.m. Pacific Time on day two. There is no 5:00 p.m. receipt cutoff or
rollover. A replacement starts a new clock at its own actual inbox receipt.

## Actual v1 purchase lifecycle

The v1 app has no user account, submission server, remote credit ledger, or
delivery-confirmation service. It does have an operator-only local SQLite
redemption ledger containing HMAC-SHA-256 digests for one-use reconciliation.
Its StoreKit behavior must be described exactly:

- A locally verified, unfinished StoreKit transaction acts as the available
  submission credit. If the customer cancels the fallback before copying the
  complete email or opening another mail app, the transaction remains unfinished
  and reusable. A saved, cancelled, failed, or unknown Apple Mail result after the
  complete body is displayed—or a copied/opened fallback—leaves it unfinished but locked
  against duplicate preparation until the customer explicitly confirms that the
  prepared email was sent or deleted without sending.
- The app records the email-handoff decision locally and finishes the StoreKit
  transaction when `MFMailComposeViewController` reports `.sent`, or when the
  customer explicitly confirms that a fallback email was sent from another mail
  app.
- `.sent` means the message was handed to the mail system or queued; it does not
  prove delivery to `info@bayareaapps.com`.
- An explicit sent confirmation also finishes the transaction. An explicit
  deleted-without-sending confirmation clears the handoff lock and makes the same
  unfinished credit reusable. Merely saving, copying, or opening the email does
  neither.
- StoreKit binds the purchase to the submission UUID using `appAccountToken`.
  The prepared email contains Apple's signed transaction JWS. For an initial paid
  submission, the operator tool must use Apple's official App Store Server
  Library to verify the emailed JWS, derive its signed transaction ID and signed
  `appAccountToken`, query Apple's App Store Server API using that signed
  transaction ID, and separately verify Apple's current signed transaction JWS.
  It must confirm the Production environment, expected app and product, matching
  signed transaction and app-account-token fields, consumable type, quantity of
  one, and no revocation before accepting the message. Only then may it atomically
  insert the HMAC-SHA-256 transaction and submission-reference digests. Raw or
  customer-edited transaction, token, environment, or submission text elsewhere
  in the email is display/support information, not a verifier input or proof.
- `UNAVAILABLE`/exit 4 is an operational hold, not acceptance or rejection; it
  must not redeem the proof or produce the paid result. The operator must preserve
  and safely retry the same JWS, tell the customer not to repurchase, and pause
  sales while an unresolved or systemic verification fault persists.
  `REJECTED`/exit 2 is a definitive invalid-proof result and creates no paid
  submission. `REPLAYED`/exit 3 identifies a prior ledger redemption and must be
  reconciled with the canonical thread rather than treated as new.
- After that finish event, v1 cannot restore an in-app credit. If the submitted
  question in a valid paid initial is medical, out of scope, or unclear, the
  operator sends a free referral and guarantees **exactly one replacement
  opportunity without another purchase**. It must be a reply from the original
  sender in the canonical email thread and reach the inbox by 11:59 p.m. Pacific
  Time on the 90th calendar day after the replacement-offer email is sent. The
  offer states the exact computed deadline. Invalid proof, fraud, or abuse does
  not establish a valid paid initial or replacement right. A clear replacement
  attempt consumes the one opportunity even if later found ineligible; free
  safety, administrative, privacy, purchase-support, provider/cost-resource, and
  autoresponse messages do not. Ambiguous intent is clarified without
  consumption. No second replacement is offered.
- An authorized replacement is authenticated by the original sender and canonical
  thread state. It never reruns or redeems the original Apple proof.
- Emergency redirects, provider-directory replies, privacy requests, and
  purchase support are free administrative messages. They are not paid answers.

This limitation and the 90-day replacement window must be visible before
purchase. Never tell a customer that a finished in-app credit was restored,
unused, or still visible in the app.

## Why the boundary is strict

California reserves the practice of veterinary medicine to licensed
veterinarians. The statutory definition includes representing oneself as
practicing veterinary medicine and diagnosing or prescribing treatment for an
animal. California's owner-assistance exception is limited to assistance given
without compensation, so it is not authority for a paid answer service.
California telehealth does not expand an assistant's scope: veterinary medicine
by telehealth must be practiced by a California-licensed veterinarian.

The Veterinary Medical Board distinguishes an unregistered assistant from a
veterinarian or registered veterinary technician and describes assistant tasks in
the context of appropriate veterinary supervision and a veterinary setting. This
public service therefore remains strictly nonmedical.

The cited authorities do not create an express safe harbor for a paid,
assistant-operated public answer service. These guardrails reduce risk; they do
not establish Board approval. Before launch, verify that “veterinary assistant”
accurately describes the operator and do not claim the operator is licensed,
registered, certified, a technician, or supervised by a veterinarian unless each
statement is currently true and counsel approves the wording.

## Eligible questions

Answer only general education that does not require evaluating an individual
animal. Examples are limited to:

- general grooming concepts that do not select a tool or product and contain no
  symptom, skin, ear, dental, injury, or other medical information;
- general enrichment, crate, litter-box, and routine-handling concepts that do
  not evaluate behavior, aggression, distress, sudden change, or safety risk;
- neutral explanations of what commonly happens during a routine veterinary
  visit, without saying what should happen for this animal; and
- general routine-visit preparation, such as writing down questions for the
  veterinarian, without reviewing medical information.

Do not provide an exercise intensity or frequency plan, individualized training
plan, product comparison, or recommendation. An eligible reply must remain
general, cite current authoritative sources, identify the operator as a veterinary
assistant rather than a veterinarian, and never imply veterinarian review,
approval, supervision, or employment.

## Always outside scope

Refer the entire submission if any part asks for, contains, or would require:

- a diagnosis, differential diagnosis, disease identification, or cause;
- an urgency, severity, triage, or “can this wait?” judgment;
- treatment, first-aid steps, home remedies, monitoring instructions, or an
  individual care plan;
- a product, food, diet, supplement, medication, or dose recommendation;
- advice to start, stop, continue, combine, substitute, or change a treatment;
- a prognosis, reassurance, prediction, or statement that veterinary care is
  unnecessary;
- review or interpretation of a photo, video, sound, medical record, test,
  imaging result, discharge instruction, prescription, or veterinarian's advice;
- symptoms, injury, poisoning or exposure concerns, pregnancy or reproduction,
  post-operative concerns, aggression, distress, sudden change, or any other
  medical or safety question; or
- information whose safe answer depends on species, age, breed, weight, history,
  examination, or current condition.

Do not decide whether a described situation is actually urgent. If the subject or
plain-text message mentions a symptom, injury, exposure, poisoning, distress,
rapid change, an emergency, or whether care can wait, use the emergency redirect
in [RESPONSE_TEMPLATES.md](./RESPONSE_TEMPLATES.md). Otherwise use the matching
referral. Do not answer a supposedly nonmedical portion of a mixed submission.

## Required free pre-purchase screen

Show the complete gate before any purchase control. Require separate affirmative
checkboxes for each statement; none may be preselected.

> **Safety check — no purchase is needed for this step**
>
> This service cannot evaluate symptoms, injuries, possible poisoning or
> exposure, emergencies, medications, doses, products, foods, diets, test
> results, records, images, treatment, prognosis, behavior or safety concerns, or
> whether care can wait. It does not provide veterinary advice or replace a
> veterinarian.
>
> If your pet may be sick, injured, exposed to something harmful, in distress, or
> changing rapidly, contact a licensed veterinarian or emergency veterinary
> hospital now. In the United States, for a possible poison exposure you may also
> contact ASPCA Animal Poison Control at (888) 426-4435; a consultation fee may
> apply. Do not wait for or purchase an answer from this service.

> **Scope confirmation**
>
> I confirm that my submission is one general, nonmedical pet-care education
> question and contains none of the excluded topics above.

> **Purchase and email confirmation**
>
> I understand that the app uses my Apple question-submission credit when Mail
> reports the prepared email as sent, or when I confirm that I sent it from
> another mail app. “Sent” may mean queued and does not prove delivery. The app
> cannot restore the credit afterward. After the complete email is displayed, a
> saved, cancelled, failed, or unknown Mail result—or a copied or opened
> fallback—locks the same unfinished credit against another prepared email until
> I confirm that the prior email was sent or deleted without sending. If my valid
> paid initial submission is ineligible, I will receive exactly one replacement
> opportunity. It does not require another purchase. I must send it from my
> original email address as a reply in the same
> thread by 11:59 p.m. Pacific Time on the exact date stated in the
> replacement-offer email, which will be the 90th calendar day after that offer is
> sent. A clear replacement attempt uses that opportunity even if it is
> ineligible, and there is no second replacement.

> **Age confirmation**
>
> I confirm that I am at least 18 years old and authorized to make this purchase.

If any confirmation is missing, do not show the purchase control. Keep urgent-care
and poison resources available for free.

## Category and prompt rules

Use exactly the four implemented categories: **General grooming concepts**,
**Enrichment & routine basics**, **Crate, litter & new-pet environment**, and
**Routine visit preparation**. Do not add a duplicate or implied fifth routing
category. Do not offer categories named for symptoms, body systems, injuries,
diseases, medicines, supplements, products, foods, diets, poisoning, tests,
behavior problems, safety concerns, or urgency.

The category step may ask only for one general, nonmedical education topic. It
must not ask for a pet's name, age, breed, weight, life stage, medical history,
medications, records, current condition, symptoms, or an image. Category routing
must not calculate a risk score, assess urgency, or suggest that a selected topic
is safe for this service.

## Purchase and advertising rules

- Product name: **One Education Question Email**.
- Exact StoreKit product display description: **One nonmedical education question email.**
  Keep this short field exact.
- The adjacent purchase surface and App Store listing—not the short product
  description alone—must disclose the complete scope, human-review result and
  timing target, actual-inbox-receipt clock, email handoff, credit-finish point,
  same-sender/canonical-thread replacement terms, refund path, and emergency
  exclusion. These disclosures must be visible before purchase.
- Show StoreKit's localized `Product.displayPrice`. Do not hard-code, round, or
  separately advertise a different price.
- Present it as a one-time consumable submission credit, not a consultation,
  appointment, hotline, priority response, subscription, or veterinarian access.
- A locally verified StoreKit credit that the app has not marked sent does not
  expire. That app state is distinct from operator-ledger redemption: the first
  `ACCEPTED` initial email atomically redeems the signed proof, and another use is
  `REPLAYED`. Before discontinuing the product, stop new sales and preserve the
  supported app path, mailbox, verifier, ledger, and capacity needed to reconcile
  device credits not marked sent, signed proofs awaiting acceptance, open
  replacement windows, and Apple refund support.
- “Help Line” can imply live or urgent assistance. Pair the
  **Veterinary Assistant Help Line** identity with **Nonmedical education by
  email — not monitored for emergencies** in primary brand placements, the App
  Store listing, and every purchase surface. Never shorten “veterinary assistant”
  to “vet,” which can be mistaken for veterinarian.
- Never advertise “medical advice,” “triage,” “diagnosis,” “treatment,” “expert
  opinion,” “ask a vet,” “vet-approved,” “pre-vetted,” “24/7,” a guaranteed
  response time or answer eligibility, or a promised health outcome. The defined
  replacement opportunity for a valid paid initial outside scope is the only
  guaranteed remedy and must always include its conditions.
- Do not state that an out-of-scope submission leaves an in-app credit available.
  Accurately describe the one same-thread replacement instead.

California prohibits untrue or misleading advertising, including statements that
mislead by omitting material facts. Price, scope, typical timing, email handoff,
replacement limit, refund path, and the fact that medical questions will not be
answered must be clear before purchase.

## Required public disclosure

Place this beside the purchase control and the email-review action:

> This is a nonmedical educational email service operated by a veterinary
> assistant, not a veterinarian. It does not diagnose, assess urgency, recommend
> treatment, products, medications, foods, diets, or doses, interpret records,
> tests, or images, or answer medical or safety questions. It is not monitored for
> emergencies. A paid submission normally receives one human review
> result—eligible answer or scope/referral—by 5:00 p.m. Pacific Time on the second
> business day after actual inbox receipt. The first business day after receipt is
> day one; business days are Monday through Friday excluding U.S. federal
> holidays, with no 5:00 p.m. receipt cutoff or rollover. This is a target, not a
> guarantee. The Apple credit is used when Mail reports the email as sent or you
> confirm fallback sending; this may mean queued, not delivered. The app cannot
> restore it afterward. After the complete email is displayed, a saved,
> cancelled, failed, or unknown Mail result—or a copied/opened fallback—locks the
> same unfinished credit until you confirm that email was sent or deleted without
> sending. If a valid paid initial is ineligible, you receive exactly one
> replacement opportunity without another purchase. It must come from your
> original email address in the same thread by 11:59 p.m. Pacific Time on the
> exact date in the offer email—the 90th calendar day after that offer is sent. A
> clear attempt uses the opportunity even if ineligible; there is no second
> replacement.

## Pre-launch operational constraints

V1 has no backend to confirm delivery, automatically enforce a replacement
entitlement, count outstanding unfinished purchases across devices, or pause
purchases remotely. The operator verifier and local one-use ledger reject forged
or replayed paid proof when used correctly, but they do not stop arbitrary email
or bind the final editable Mail body to that proof. V1 also has no location
verification. Before launch:

- test and document the actual StoreKit/Mail lifecycle, crash recovery, fallback
  confirmation, missing-email support, and manual same-thread replacement;
- verify every initial paid email using Apple's official server library, a live
  current-transaction lookup keyed by the transaction ID derived from the signed
  emailed JWS, and the atomic HMAC redemption ledger; keep root certificates
  current and trusted, protect the Apple API credentials, keep the ledger
  encrypted and backed up, and keep Production completely separate from Sandbox;
- route verifier `UNAVAILABLE` results to `PAYMENT-HOLD`, never manual acceptance
  or rejection; safely retry the same proof, request no repurchase, and pause new
  sales while the fault is unresolved or systemic;
- operate the mailbox from a dedicated encrypted device/profile in plain-text
  view, with remote images, link previews, and automatic attachment downloads
  disabled; never click customer links; validate SPF, DKIM, and DMARC
  `Authentication-Results` for every legitimate sender before staged hard-fail or
  reject policies, and assess MTA-STS and TLS-RPT as specified in the operator
  workflow;
- establish a tested App Store/operator procedure to stop new purchases, allow
  for propagation delay, and pause well before capacity is exhausted;
- do not scale beyond the volume the operator can reconcile manually; and
- obtain legal review for every jurisdiction where the app can be acquired or
  used. These California guardrails do not resolve other jurisdictions' laws, and
  v1 must not claim that it limits use to California.

If a safe stop-sale procedure and adequate workload buffer do not exist, keep the
paid product unavailable until a remote capacity control is implemented.

## Privacy boundary

Before send, the question draft remains in the app. Opening a composer shares the
prepared content with the device's mail service even if the customer later
cancels. When the customer sends, the customer's and operator's email providers
process the message under their own terms. Collect in the email only a
StoreKit-bound submission reference, Apple transaction reference, environment,
signed JWS proof, reply address, and the one eligible question. The JWS may
contain Apple purchase metadata described in the privacy policy. Do not request a
pet's name or demographics, images, recordings, medical records, test results,
precise location, government ID, payment-card data, Apple Account password, or
two-factor code.

The separate redemption ledger may contain only HMAC-SHA-256 transaction and
submission-reference digests, environment, and redemption time. It must not hold
email, question, or JWS content. Keep it encrypted, access-controlled, backed up,
and separate from Sandbox. Preserve its HMAC key without unplanned rotation for
the life of the paid service; losing or rolling back either ledger or key requires
pausing paid acceptance until reconciliation. Apply the retention and deletion
rules in the operator workflow.

Bay Area Apps must not intentionally submit customer content to a generative-AI
service or use it for advertising, marketing, or model training. Follow the
retention and deletion procedure in [SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md) and
accurately disclose email-provider and Apple processing that the operator does
not control.

Record explicit closure and purge dates. A closed answer/referral thread is
deleted from operator-controlled locations 90 calendar days after its final
response. A thread with an unused replacement right stays open through the exact
disclosed deadline; if no replacement arrives, that deadline is its closure date
and the content is deleted 90 calendar days later. If a timely replacement arrives,
its final response becomes the closure date and the content is deleted 90 calendar
days later.
Free administrative/support messages and definitively rejected proof are also
deleted 90 calendar days after their final reply—or receipt when no reply is
warranted—unless an unexpected attachment or deletion request requires earlier
removal. A documented, time-bounded legal, security, fraud, accounting, or active
dispute need is the only longer-retention exception.

Replay-prevention hashes remain only for the paid service's life. The service is
truly ended only after sales stop and device credits not marked sent, proofs
awaiting reconciliation, payment holds, open submissions, disputes, and
replacement windows are resolved. Delete those hashes within 90 days after the
recorded service-end date unless a documented, time-bounded legal, security,
fraud, accounting, or dispute need requires longer.
Apply that deletion deadline to every operator-controlled ledger backup, replica,
export, and retired HMAC-key copy, with provider-managed backup media limited to
the disclosed contractual schedule.

## Authoritative California and safety sources

- [California Business and Professions Code §§ 4825–4831](https://leginfo.legislature.ca.gov/faces/codes_displayText.xhtml?article=2.&chapter=11.&division=2.&lawCode=BPC&part=&title=)
  — licensure requirement, practice definition, exceptions, and penalties.
- [California Business and Professions Code § 4826.6](https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=4826.6.)
  — veterinary medicine by telehealth and veterinarian-client-patient relationship.
- [California Business and Professions Code § 4853](https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=4853.)
  — limits on furnishing veterinary services through artificial entities.
- [California Veterinary Medical Board: Veterinary Office Staff](https://www.vmb.ca.gov/applicants/vet_office_staff.shtml)
  and [Animal Health Care Tasks](https://www.vmb.ca.gov/laws_regs/rvttasks.shtml)
  — role distinctions and supervision framework.
- [California Business and Professions Code § 17500](https://leginfo.legislature.ca.gov/faces/codes_displaySection.xhtml?lawCode=BPC&sectionNum=17500.)
  and [California Attorney General: Hidden Fees](https://oag.ca.gov/hiddenfees)
  — truthful advertising and clear total-price presentation.
- [California Attorney General: Online Privacy Policy Requirements](https://oag.ca.gov/privacy/facts/online-privacy/privacy-policy)
  — CalOPPA privacy-policy guidance.
- [ASPCA Animal Poison Control](https://www.aspca.org/pet-care/aspca-poison-control)
  — current poison-control contact information and fee disclosure.
