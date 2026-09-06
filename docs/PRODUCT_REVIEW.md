# Pet-parent product review — September 6, 2026

The service should sell a useful human-written explanation or organizer within Jahmal’s role. It must not imply that paying obtains a clinical assessment from a veterinarian. Many likely pet-parent questions are medical; forcing all of them into paid categories would create the wrong service.

## Decisions carried into the code

| Finding | Correction |
|---|---|
| Client-facing iOS purchases contradicted the private-phone requirement | One public website and one private operator iPhone inbox, connected through one server |
| A referral-only answer did not justify a paid question | Free referral plus full original-method refund; removed replacement-credit obligation |
| General categories could invite clinical questions | Five narrower topics, specific exclusions, free scope help and human review |
| Clients needed help formulating a useful request | Three distinct examples per category, relevant context prompt and checklist/explanation preference |
| A generic disclaimer could be mistaken for the service delivered | Direct answer, practical content, relevant limit and checked sources required before publication |
| A follow-up could become another unnecessary purchase | One same-topic clarification on the original receipt with its own response target |
| Email or checkout interruption could lead to duplicate payment/reply | Immutable draft and idempotent checkout, verified payment, durable Mail handoff state |
| Repeated hard-coded policy lists could drift | One JSON catalog used by web/server/native app; cross-surface checks for fixed legal pages |
| Shared data exposed owner writing guidance and service notes to client requests | Explicit client field allowlists; full guide requires owner authentication, private notes stay private, and customer receipts use status notices |
| Client copy described the private iPhone setup and internal payment/email workflow | Customer pages now focus on service and purchase information; implementation and business decisions remain in private operator materials |

## Realistic question and response map

These are product scenarios, not diagnoses or automated responses. “Paid” means potentially eligible after reading the whole request; none of these examples establishes that an individual animal is healthy or safe.

| Pet parent asks | Route | Useful response or handling |
|---|---|---|
| What should I ask at a first grooming appointment? | Grooming | A short preparation list and questions for the person handling the animal; no procedures or product selection |
| What does introducing brushing gradually mean? | Grooming | Explain the concept generally; no restraint plan, prescribed schedule or assessment of tolerance |
| How close should I cut this nail? | Free veterinary/grooming referral | No measurements, photograph review or procedural coaching; refund if paid |
| There is a broken or bleeding nail. What can I do? | Free veterinary route | Direct to a veterinarian; no paid waiting or first-aid treatment instructions |
| What should I organize before bringing a pet home? | Home | A nonmedical preparation sequence and editable list of spaces, existing supplies and responsibilities |
| How can I set up a quiet settling-in area? | Home | General organizational considerations; no individualized safety approval or confinement rules |
| Is it safe to leave these animals together? | Free professional route | Do not assess behavior, safety or suitability from a message |
| Why keep a carrier familiar at home? | Home | Explain the general concept from a relevant source, excluding drug and product advice |
| What is enrichment? | Routines | Plain-language explanation plus an example of an activity organizer; no exercise prescription |
| How can I keep enrichment ideas organized? | Routines | Rotation/list headings, not a claim that each proposed activity is safe for a particular pet |
| How much exercise does my dog need? | Free veterinary route | Individual limits require a qualified professional; no duration/intensity prescription |
| My pet is suddenly hiding or having litter accidents. | Free veterinary route | Sudden changes are outside this service; do not classify as a routine behavior issue |
| Who are the vet, technician and assistant? | Visits | Explain roles using the applicable licensing-board source without claiming this service is supervised |
| How can I organize my questions before a routine visit? | Visits | A blank priority/question-list structure, with no interpretation of the medical answers |
| Should I fast my pet before the appointment? | Free treating-clinic route | Obtain instructions directly from that clinic; do not invent or interpret them |
| Is this estimate necessary, or what do these results mean? | Free treating-clinic route | No clinical, financial-necessity or record interpretation |
| What headings belong in a sitter handover? | Organization | Contacts, agreed nonmedical tasks, supply locations and check-in arrangements; no personal details in intake |
| How do we avoid household members duplicating tasks? | Organization | A task/owner/completed-time checklist; this category owns handovers so it is not duplicated under routines |
| Can you make a medication schedule for my sitter? | Free treating-clinic route | No administration plan, dose calculation or interpretation |
| Which food or supplement should I buy? | Free veterinary route | No diet or product recommendation |
| My pet swallowed something, is vomiting, or cannot urinate. | Free urgent veterinary route | Immediate veterinary/emergency direction visible before payment; no wait-time reassurance |
| Can this wait until tomorrow? | Free urgent veterinary route | The service cannot decide urgency; do not accept payment to make that decision |
| Where is a clinic, and what does it charge? | Free clinic/admin information | Contact clinic directly; do not charge for a phone number, estimate request or referral |
| I paid twice, lost my link, or did not get a reply. | Free support | Verify original email/payment reference; reconcile without another purchase |
| Can you explain this part of your answer? | Included clarification | One same-topic explanation, no second payment, deadline shown on receipt |

The automatic word filter catches some obvious medical wording. Negation, misspellings, descriptions without the keywords and mixed topics may pass it; human review and full refunds are the backstop. Do not expand the filter into an “AI triage” claim or add a paid medical catch-all.

## Price and value

Retain a single **$9.99 USD** price across all five categories. There is no evidence of actual customer demand or measured writing time yet, so a higher price or category-specific surcharge would be guesswork. The paid value is the individual explanation/checklist and included clarification. Free medical referral, basic clinic information and account support should not be monetized.

Competitive context: Chewy advertises free licensed-vet-tech chat in its [Connect with a Vet overview](https://www.chewy.com/b/connect-vet-16616), while its [virtual visit offer](https://www.chewy.com/pethealth/connect-with-a-vet/virtual-visit) concerns licensed-veterinarian appointments. Neither establishes a market rate for an independent assistant’s nonmedical education. Do not market this service as equivalent to licensed veterinary telehealth.

Budget roughly 15–20 minutes total per question including the clarification when evaluating feasibility; this is a planning assumption, not a promise about work time. At $9.99, 20 minutes represents $29.97/hour in gross receipts before processing fees, refunds, hosting, taxes and unpaid administration. Check actual Stripe account pricing rather than assuming a fee schedule. Review the first twenty completed cases manually for time, clarity and refund frequency. No automatic price changes are implemented. If the answer only repeats free guidance, make that information free or refund it instead of padding the reply.

## Response acceptance standard

The reply must identify the question being answered, directly explain the requested nonmedical concept, give a practical example or checklist, and link one to three relevant authoritative sources actually checked. State the pertinent boundary briefly. Do not copy unrelated medical, product or handling advice from a linked article. There is no mandatory word count in the service promise; API size limits prevent an empty or excessively large response.

The normal target is 5 p.m. Pacific on the second business day after verified payment. Calendar calculations exclude weekends and observed U.S. federal holidays, including the previous-year observation of New Year’s Day. Clarifications may be requested until the end of the seventh calendar day after first publication and have the same business-day response target. Client cancellation before a substantive answer blocks further publication. A delayed response does not force a replacement purchase.

## Verification and launch limits

Automated checks exercise all fifteen examples, representative medical exclusions, credentials, signed webhooks, amount matching, replay, delayed-webhook recovery, canceled-question races, refund persistence, clarification limits, response dates, retention and Mail handoff state. Native tests cover catalog decoding, server JSON compatibility, connection validation and private-inbox state. Repository checks cover assets/links, required UI IDs, policies and removal of the old purchase workflow.

These checks do not prove live Stripe activation, Apple Pay eligibility, email delivery, real-device behavior, production hosting security or legal approval. The test-to-live checks in `SOLO_WORKFLOW.md` remain required. This work updates the existing review branch; it does not publish a live service or install the app on an iPhone.

Primary scope/payment references: [California VMB staff roles](https://www.vmb.ca.gov/applicants/vet_office_staff.shtml), [VMB authorized tasks](https://www.vmb.ca.gov/laws_regs/rvttasks.shtml), [Stripe Checkout fulfillment](https://docs.stripe.com/checkout/fulfillment), [Stripe refunds](https://docs.stripe.com/refunds), [Stripe Python resource conversion](https://github.com/stripe/stripe-python#working-with-api-resources). The chosen product boundaries are a conservative design decision, not a determination that this independent service is legally authorized in every jurisdiction.
