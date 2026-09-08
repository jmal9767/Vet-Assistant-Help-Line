# Service delivery and client promises

The price/value revision is based on `main` commit
`6d21e36e1b49e252ed35b485caaa35907ea9c685`, which contains the current banner.
The separate production-consolidation draft has a different checkout/catalog
model; this change does not merge or replace that work.

## Before payment

1. Review the request within two business days. Symptoms, medications, urgency
   decisions and other medical questions go to a veterinarian, without a paid
   answer. A referral alone is not a paid deliverable.
2. Read the requested service and delivery preference at the top of the question.
   The form preserves them in both the email handoff and CloudKit question text.
3. Collect missing context before confirming the offer. State the one pet and
   one care topic, deliverables, total price, exact deadline (including timezone)
   or appointment, included clarification and refund terms in the quote.
4. Accept only work that can meet the advertised timing. Payment must arrive
   within the validity period stated in the quote. If payment arrives later,
   offer a new confirmed deadline or a full refund; never silently extend it.
5. Keep a record of the client's agreement and payment. Quotes, appointments,
   deadlines, follow-up and refunds are handled manually in this branch.

## What must be delivered

- **Focused written answer, $10:** address one straightforward nonmedical care
  question using the provided context. Include a personal explanation and useful
  next steps. Email or text costs the same. Due within one business day after
  confirmation and payment.
- **Detailed written guide, $20:** address related questions within one topic;
  include ordered steps, a checklist and relevant, verified resources. Deliver
  by email within two business days after confirmation and payment.
- **Live text session, $25:** reserve 20 minutes for the conversation on the
  agreed topic, including the client's questions. Email a recap of the discussed
  steps within one business day after the session.
- **Phone support session, $35:** reserve 30 minutes for the conversation on the
  agreed topic, including the client's questions. Email a recap within one
  business day after the session. Do not describe this as a veterinary consult.

Use templates as a starting point and tailor the response to the question.
Do not promise a diagnosis, a medical outcome or savings on veterinary bills.
If meaningful educational help cannot be provided, decline or fully refund.

## Timing and clarification

Business days are Monday–Friday, excluding U.S. federal holidays, in Pacific
Time. Confirm an exact date and time, not just "tomorrow". For example, a focused
answer confirmed and paid Friday at 2 p.m. is due Monday at 2 p.m.; if Monday is
a federal holiday, it is due Tuesday at 2 p.m. A detailed guide under the same
conditions is due Tuesday, or Wednesday when Monday is a holiday.

Every option includes one written clarification on the original topic, requested
within seven calendar days of the first answer or session. The clarification
receives one written reply within two business days. This is neither seven days
of unlimited messaging nor another live appointment. New topics or pets require
a separate quote and client agreement; there are no automatic extra charges.

## Refunds and cancellations

Keep the existing full satisfaction guarantee: if the client does not feel their
question was answered, they may reply to request a full refund. Also fully refund
an out-of-scope or referral-only result, a cancellation before the answer/session,
or a missed deadline when requested. Release an uncaptured authorization; refund
a captured payment through the processor. Do not advertise automatic refunds.

The existing payment worker can capture an authorization after 24 hours measured
from creation of the payment intent, **without knowing whether an answer was
delivered**. The banner therefore makes no "only charged after an answer" claim.
Do not promise delayed capture or client-approval-only capture. The worker's
payment architecture is outside this copy/menu change.

## Menu maintenance

Edit `service-menu.json`, run `python3 scripts/sync_service_menu.py`, and run
`python3 scripts/sync_service_menu.py --check`. Static web menus and the native
share card are generated from the same source. The poster uses shortened terms
and points to the full menu before payment. The PWA cache version is advanced
with this revision so installed clients can refresh the displayed menu.

## Review basis (September 8, 2026)

The old menu charged more for the same quick answer by text, compressed two
prices into one row, left follow-up undefined and advertised both a 24–48-hour
wait and an emergency decision. The revision charges for depth or reserved
conversation time, states concrete takeaways and removes express surcharges.
The prices are a service-design judgment, not a validated demand forecast.

Current comparison: [Chewy's own service page](https://www.chewy.com/b/connect-vet-16616)
offers free technician chat and lists licensed-veterinarian virtual visits at
$49.99. That makes a $45 assistant "full consult" difficult to distinguish.
The revised $35 phone session is explicitly educational, with a saved recap and
one clarification; it is not advertised as equivalent to a veterinarian visit.

Role boundaries were checked against the
[California Veterinary Medical Board's task regulations](https://www.vmb.ca.gov/laws_regs/rvttasks.shtml)
and [telehealth FAQ](https://www.vmb.ca.gov/licensees/ab1399_faqs.shtml).
The paid examples now focus on nonmedical care organization and preparation.
