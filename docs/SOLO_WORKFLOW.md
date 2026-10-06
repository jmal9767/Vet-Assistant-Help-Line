> Updated October 5, 2026: new written requests use **private website conversations** answered directly in the app. Email/Text references below apply to historical requests or optional integrations. See [private conversations](PRIVATE_CONVERSATIONS.md) for the current workflow.

# Solo operator workflow

## New question

1. Open the iPhone app and review emergency warning signs first.
2. If the message may describe an emergency, send the Emergency Redirect template immediately.
3. Review the client-selected service and question. Paid requests wait for your approval while you are busy. Tap **Approve — I’m Available** to enable payment, or **Decline — Unavailable** to archive without charging. The client sees the decision on their private conversation page.
4. Review the question and private files. Files may be any type, up to four files and 10 MB each. Download unfamiliar file types only when you recognize and trust the client submission.
5. Decide whether the request is within the educational scope. Refer diagnosis, medication, dosing, treatment, prognosis, diagnostic interpretation, and other clinical decisions to a licensed veterinarian; refund a paid request when you cannot provide the selected service.
6. For paid options, confirm payment before beginning the response. Free Community Support requires no payment. PayPal and Apple Pay update automatically. No payment-link messages or manual payment-status changes are needed.
7. Tap Reply in Care Line, write the response with the standard disclaimer, and tap Send Care Line Reply. A delivered reply marks the question answered; a client follow-up marks it new when CloudKit sync succeeds. For Phone Support, arrange and make the call separately.
8. Archive completed questions. Archived questions remain available in the Inbox’s Archived filter.

## Before every response

- Did the response diagnose, prescribe, dose, treat, interpret tests, or promise an outcome? Rewrite or refer.
- Could the pet need urgent care? Direct the client to a veterinarian or emergency hospital.
- Does the client understand that the service is general education from a veterinary assistant?
- Is the standard scope and emergency reminder included?

## Payments

The client chooses $10 Quick Question, $15 Detailed Guidance, $25 Phone Support, or Free Community Support before submitting. After your availability approval, paid clients open checkout from their private conversation page; Free Community Support requires no payment and no explanation. Card and bank information stays with the payment provider.

## Privacy and retention

Use private conversations for new written replies. Use info@bayareaapps.com only for support or historical email requests. Do not place server secrets in the app or website. Private file links expire after 30 days, and the R2 bucket should delete uploaded objects after 30 days. Handle deletion or correction requests through the client’s existing contact channel.

Scheduling messages do not close a request awaiting approval or payment. Declined requests stay archived when the client sends a follow-up. Restoring a declined request moves it back to Awaiting approval; it never enables payment by itself.
