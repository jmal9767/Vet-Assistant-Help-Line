# Response Templates

These are the approved customer-response patterns for the narrow service defined
in [LEGAL_SCOPE.md](./LEGAL_SCOPE.md). The operator must personally read every
plain-text question and write every substantive answer. Do not use generative AI
to ingest, classify, summarize, draft, rewrite, translate, select, or send a
customer question or reply.

Follow the mail and replacement workflow in
[SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md). V1 finishes the Apple transaction when
Mail reports the question email as sent/queued or the customer confirms fallback
sending—not when the operator answers. The operator cannot restore that in-app
credit. An initial ineligible submission receives a free referral and one
guaranteed replacement opportunity when it is a valid paid initial. The
replacement must come from the original sender in the same canonical thread by
the exact disclosed deadline. Invalid proof, fraud, or abuse does not establish a
valid paid initial. Emergency, administrative, privacy, provider/cost-resource,
and purchase-support replies are free and do not consume a replacement.

## Replacement paragraphs

For a non-emergency out-of-scope or unclear response, append exactly one of these
paragraphs after determining the thread status. For an emergency, send the safety
redirect immediately without waiting for purchase verification. Afterward, check
the thread and proof; send the applicable paragraph as a separate reply in the
same thread only when a verified initial submission or authorized replacement is
associated with the emergency message.

**Initial paid submission — replacement not previously offered**

> This valid paid initial submission is outside the service's scope, so you have
> exactly one replacement opportunity without another purchase. From the same
> email address that sent the initial submission, reply in this same email thread
> with one general, nonmedical education question. Your replacement must reach
> this inbox no later than **[EXACT DEADLINE: Month DD, YYYY, at 11:59 p.m.
> Pacific Time]**, the 90th calendar day after this replacement-offer email is
> sent. The app cannot restore or display the finished credit, so keep this
> thread. A clear replacement attempt uses the opportunity even if it is outside
> scope, and there is no second replacement.

Before sending, replace the bracketed placeholder with the exact computed date;
never send a relative-only “within 90 days” deadline. Then label the thread
`REPLACEMENT-OFFERED` and record the offer timestamp and deadline.

A clear attempt to submit the replacement question consumes the one opportunity,
even if later found outside scope. A thanks, administrative, privacy,
purchase-support, provider/cost-resource, autoresponse, or safety-only message
does not consume it. If intent is genuinely ambiguous, clarify intent without
consuming the right or soliciting animal or health details.

**The one replacement was already submitted**

> This was your one replacement attempt, and it is outside the service's scope.
> I cannot answer it or offer a second replacement. If you want Apple to
> review a refund request, visit
> [reportaproblem.apple.com](https://reportaproblem.apple.com/). Apple decides
> refund eligibility.

Label the thread `REPLACEMENT-CLOSED`. Do not ask for another purchase.

**The 90-day replacement window expired**

> Your disclosed replacement deadline—**[EXACT DEADLINE: Month DD, YYYY, at
> 11:59 p.m. Pacific Time]**—has passed, so I cannot accept this message as the
> paid replacement or provide a paid answer. If you want Apple to review a refund
> request, visit
> [reportaproblem.apple.com](https://reportaproblem.apple.com/). Apple decides
> refund eligibility.

Label the thread `REPLACEMENT-CLOSED`. Do not ask for another purchase while a
refund or purchase dispute is open.

Replace the bracketed placeholder with the deadline recorded on the canonical
thread before sending this response.

**No paid submission is associated with the message**

Do not append a replacement paragraph. Provide the free safety or administrative
reply only.

## 1. Fixed receipt acknowledgment

This may be sent by a deterministic mailbox rule after an email arrives. It is
only a receipt, not payment acceptance, a scope decision, or a substantive answer.
Send no more than one receipt for each eligible human-origin message. Suppress mail
from the service's own address; `Auto-Submitted` or otherwise automated messages;
bulk or list mail; delivery-status notifications, postmaster/mailer-daemon messages,
and bounces; and any message already marked receipt-sent. The rule must set that
idempotency marker atomically before sending. If no submission reference is
present, use the neutral subject **Message received — Veterinary Assistant Help
Line**; do not invent a reference.

**Subject:** Question email received — [SUBMISSION REFERENCE]

> We received your email. This receipt is not acceptance of Apple payment proof,
> confirmation of a valid paid submission, or a scope decision. If the proof is
> accepted as a valid paid initial submission, or this message is confirmed as
> the one authorized replacement, we normally send one human review result—either
> an eligible educational answer or a scope/referral response—by
> 5:00 p.m. Pacific Time on the second business day after the email actually
> reaches this inbox. Business days are Monday through Friday, excluding U.S.
> federal holidays. The first business day after receipt is day one. There is no
> 5:00 p.m. receipt cutoff or rollover. This timing is a target, not a guarantee.
>
> This inbox is not monitored for emergencies. If your pet may be sick, injured,
> exposed to something harmful, in distress, or changing rapidly, contact a
> licensed veterinarian or emergency veterinary hospital now. For a possible
> poison exposure in the United States, you may also contact ASPCA Animal Poison
> Control at (888) 426-4435; a consultation fee may apply. Do not wait for an
> email response.
>
> Please do not send images, recordings, medical records, test results, payment
> card information, passwords, or verification codes.

## Payment verification delay

Use only after the production verifier reports `UNAVAILABLE` (exit 4). This is a
temporary operational hold, not an acceptance, rejection, or replay result.

**Subject:** Apple payment verification delayed — [HOLD REFERENCE]

> We received your email, but the required Apple payment verification is
> temporarily unavailable. This is not a rejection, and we have not accepted or
> manually redeemed the purchase. Please do not purchase again or send different
> proof. We will safely retry the same Apple-signed proof and update you after a
> definitive result. This delay does not restart the response-time target, which
> began when your email actually reached this inbox. Your temporary hold reference
> is [HOLD REFERENCE].

Add `PAYMENT-HOLD` and follow the hold-and-stop-sale procedure in
[SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md). Preserve the original message and signed
JWS unless an unexpected attachment requires the workflow's proof-only encrypted
temporary file and immediate deletion path. Never substitute this notice for the
paid human review result.

## 2. Emergency or possible-exposure redirect

Use whenever the subject or plain-text body mentions symptoms, injury, possible
poisoning or exposure, distress, rapid change, an emergency, or whether care can
wait. This is a blanket safety redirect, not an urgency assessment.

**Subject:** Please contact a veterinarian now — [SUBMISSION REFERENCE]

> I cannot assess your pet, determine urgency, or provide medical or first-aid
> instructions. Please contact a licensed veterinarian or emergency veterinary
> hospital now and describe the concern. Do not wait for a reply from this
> service.
>
> If a possible poison exposure is involved in the United States, you may also
> contact ASPCA Animal Poison Control at (888) 426-4435; a consultation fee may
> apply. Do not wait for this email service.

Send the safety text above immediately; do not delay it to run the Apple verifier
or decide replacement status. Then apply the replacement-paragraph instructions
above. Do not offer a possible diagnosis, symptom checklist, treatment step,
timeline, reassurance, or opinion about the severity of the situation.

## 3. General medical or safety referral

Use for any other medical or safety question, including a request to evaluate a
condition, recovery, reproduction concern, behavior problem, or need for
veterinary care.

**Subject:** This question needs a veterinarian — [SUBMISSION REFERENCE]

> I am a veterinary assistant, not a veterinarian. I cannot evaluate an
> individual animal, answer medical or safety questions, diagnose, assess urgency,
> recommend treatment, or say whether veterinary care can wait. Please contact a
> licensed veterinarian and share the concern directly with them.

Append the correct replacement paragraph. Do not explain likely causes, list
warning signs, reassure the customer, or give conditional “if/then” instructions.

## 4. Medication, supplement, food, diet, or product referral

Use even when an item is sold over the counter, described as natural, or was
recommended by someone else.

**Subject:** Product or dosing questions need a veterinarian — [SUBMISSION REFERENCE]

> I cannot recommend, compare, select, start, stop, substitute, combine, or
> calculate a medication, dose, supplement, food, diet, grooming item, device, or
> treatment product. Please ask a licensed veterinarian who can evaluate the
> animal and the complete situation.

Append the correct replacement paragraph. Do not repeat a label dose, convert
units, rank products, link to a seller, or describe one choice as safer.

## 5. Image, record, test, or veterinarian-advice referral

Use for photos, video, audio, records, lab values, imaging, discharge documents,
prescriptions, or requests to review what a veterinarian said.

**Subject:** This material cannot be reviewed here — [SUBMISSION REFERENCE]

> This service does not accept or interpret images, recordings, medical records,
> test results, prescriptions, discharge instructions, or a veterinarian's advice.
> Please contact the veterinarian who examined your pet, or another licensed
> veterinarian, for review and follow-up. I did not review the attachment or
> medical material.

Append the correct replacement paragraph. Do not open, preview, download,
forward, describe, or intentionally process an unexpected attachment. First read
only the subject and plain-text body for emergency language, send the emergency
redirect if triggered, then follow the deletion steps in
[SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md).

## 6. Eligible nonmedical education answer

Use only after every item in the pre-send checklist is “yes.” Write the answer
yourself and keep it general.

**Subject:** General pet-care education — [SUBMISSION REFERENCE]

> Hi [CUSTOMER NAME OR “there”],
>
> You asked for general education about [NEUTRAL TOPIC].
>
> [TWO TO FOUR SHORT PARAGRAPHS OF GENERAL, NONMEDICAL EDUCATION. Do not refer to
> the customer's animal as though it was evaluated. Do not diagnose, assess
> urgency, provide reassurance or prognosis, recommend any product, or give
> medical or individualized instructions.]
>
> Sources:
>
> - [AUTHORITATIVE SOURCE TITLE AND DIRECT LINK]
> - [OPTIONAL SECOND AUTHORITATIVE SOURCE TITLE AND DIRECT LINK]
>
> [STANDARD SCOPE FOOTER]

Use current primary sources where available, such as a government agency,
university extension, veterinary medical board, or source organization for a
public program. A citation does not make an otherwise prohibited answer safe.

The answer closes the initial or authorized-replacement thread. Do not discuss an
Apple credit in the answer; the app already finished the transaction at email
submission.

## 7. Neutral provider or financial-resource directory

This is a free administrative reply. Do not present a provider, payment product,
or charity as endorsed, available, affordable, or suitable.

**Subject:** Resources for finding veterinary care — [SUBMISSION REFERENCE]

> This service cannot assess your pet or recommend a particular provider or
> financing option. You can search for a California veterinarian and verify a
> license through the [California Veterinary Medical Board license
> search](https://search.dca.ca.gov/). You may also contact local animal shelters,
> humane organizations, or veterinary schools directly to ask what services or
> financial-assistance information they currently offer.
>
> Availability, eligibility, price, and services can change; please verify them
> directly. This is a free administrative response, not veterinary advice.

If the original valid paid initial submission itself requested this directory,
append the initial replacement paragraph. A pure provider/cost-resource message
in a thread already labeled `REPLACEMENT-OFFERED` is free: answer it without
changing that label or consuming the replacement. If no paid right is associated
with it, append no replacement paragraph. If the message also contains a symptom,
injury, exposure, or urgency concern, send the emergency redirect before this
administrative information. Never delay the redirect to research cost resources.

## 8. Ineligible or unclear nonmedical submission

Use when the message is nonmedical but is too vague, contains more than one
question, or requests a service other than one general education answer.

**Subject:** Please send one eligible education question — [SUBMISSION REFERENCE]

> I cannot answer the current submission because [IT CONTAINS MORE THAN ONE
> QUESTION / THE REQUEST IS UNCLEAR / IT REQUESTS A SERVICE THIS PRODUCT DOES NOT
> OFFER]. This service answers one clearly stated, general, nonmedical pet-care
> education question.

Append the correct replacement paragraph. Do not ask follow-up questions about a
pet's age, breed, weight, health, history, medicines, current condition, or safety.
If any medical or safety content is present, use the matching referral instead.

The replacement receives a new response clock at its own actual inbox receipt.
Its human review result—eligible answer or scope/referral—is normally due by 5:00
p.m. Pacific Time on the second business day after receipt, using the same
business-day definition and no receipt cutoff or rollover.

## 9. Mail handoff or missing-email support

**Subject:** Question email support — [SUBMISSION REFERENCE]

> The v1 app has no submission server and cannot confirm email delivery.
> Apple Mail's “sent” result can mean the message was queued. Please check the
> sending account's Outbox and Sent folders. If the exact prepared message is in
> Sent but you did not receive a receipt from us, forward or resend that same
> message to `info@bayareaapps.com`; do not purchase again.
>
> If you used another mail app, the app finished the credit only after you
> confirmed that you sent the prepared email. After a complete email is displayed,
> a saved, cancelled, failed, or unknown Mail result—or a copied or opened
> fallback—locks duplicate preparation until you confirm whether it was sent or
> deleted without sending. Resolve that status in the app; do not purchase again.
> If the app cannot resolve it, contact
> `info@bayareaapps.com` with the submission reference and Apple purchase
> reference shown in the prepared message. Do not send payment-card information,
> an Apple Account password, or a verification code.

Do not promise that v1 can restore a finished credit. Treat an exact resend caused
by mail handoff failure as the original submission, not as the one replacement.

## 10. Apple purchase or refund support

**Subject:** Purchase support — [SUBMISSION OR APPLE PURCHASE REFERENCE]

> If you purchased but did not send or confirm sending, reopen the app before
> purchasing again; the app should recover a verified unfinished transaction as
> the available submission credit. After the complete email is displayed, a
> saved, cancelled, failed, or unknown result—or a copied/opened fallback—must
> first be marked sent or deleted without sending; it is not silently made
> reusable. If the credit or resolution control does not appear, contact us
> with the Apple purchase reference. Do not purchase again while the issue is
> unresolved.
>
> After Mail reports the question as sent, or after you confirm fallback sending,
> v1 finishes the transaction and cannot restore the in-app credit. An initial
> ineligible question with valid paid proof receives exactly one replacement
> opportunity without another purchase, from the original sender in the canonical
> thread by the exact deadline in the replacement-offer email.
>
> Apple handles App Store charges and refund decisions. To request a refund, visit
> [reportaproblem.apple.com](https://reportaproblem.apple.com/). We cannot promise
> or approve an Apple refund.

Do not claim to validate a transaction on a Bay Area Apps server; v1 has none.
Escalate an unverified or missing unfinished transaction, repeated StoreKit
failure, or apparent duplicate charge under [SOLO_WORKFLOW.md](./SOLO_WORKFLOW.md).

## 11. Privacy or deletion acknowledgment

**Subject:** Privacy request received — [REQUEST REFERENCE]

> We received your privacy request. We may need to confirm control of the customer
> email address already associated with the correspondence and the submission or
> Apple purchase reference already in that thread. We will not ask for government
> ID, payment-card details, an Apple Account password, or a verification code.
>
> We will delete or de-identify service content controlled by Bay Area Apps within
> 30 calendar days unless a documented legal, security, fraud, accounting, or
> transaction-dispute need requires limited information to be kept. We will
> confirm completion or explain what limited information remains and why. Apple,
> the sending email provider, and copies on your devices apply their own policies
> and are not controlled by Bay Area Apps.

## Standard scope footer

Append this footer to every eligible education answer:

> This is general, nonmedical education from a veterinary assistant, not
> veterinary advice. I have not examined your pet and cannot diagnose, assess
> urgency, recommend treatment, products, medications, foods, diets, or doses,
> interpret records, tests, or images, provide prognosis, or answer medical or
> safety questions. If your pet may be sick, injured, exposed to something
> harmful, in distress, or changing rapidly, contact a licensed veterinarian or
> emergency veterinary hospital now; do not wait for this email service.

## Mandatory pre-send checklist

Every item must be **yes** before sending an eligible answer. If any item is no or
uncertain, send the matching referral and apply the correct replacement status.

- [ ] The submission is the valid initial paid email or the one authorized
      replacement from the original sender in the canonical thread; it is not an
      unauthorized second replacement.
- [ ] It asks exactly one general, nonmedical education question.
- [ ] It contains no symptom, injury, exposure, poisoning, distress, behavior or
      safety problem, reproduction, post-operative, or other medical concern.
- [ ] The reply makes no diagnosis, differential, severity, urgency, reassurance,
      or prognosis judgment and never says care can wait.
- [ ] The reply gives no treatment, first aid, home remedy, monitoring plan,
      individualized exercise or training plan, product, food, diet, supplement,
      medication, or dose recommendation.
- [ ] The reply does not review or interpret an image, recording, record, test,
      prescription, discharge instruction, or veterinarian's advice.
- [ ] The answer does not depend on the individual animal's species, age, breed,
      weight, history, examination, or current condition.
- [ ] The wording says “veterinary assistant,” never veterinarian, doctor,
      clinician, consultation, or medical expert, and does not imply veterinarian
      review, approval, supervision, or employment.
- [ ] Each factual claim was checked against a current authoritative source, and
      direct source links are included.
- [ ] The operator did not use generative AI to ingest, classify, summarize,
      draft, rewrite, translate, select, or send customer content or the reply.
- [ ] The recipient, submission reference, thread status, source links, and
      standard footer are correct.
- [ ] The operator will close the mailbox thread after this eligible answer and
      will not claim that sending the answer consumes or restores an app credit.
