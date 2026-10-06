> Updated October 5, 2026: new written requests use **private website conversations** answered directly in the app. Email/Text references below apply to historical requests or optional integrations. See [private conversations](docs/PRIVATE_CONVERSATIONS.md) for the current workflow.

# Paws & Whiskers Care Line

A private iPhone operator app and public client website for general dog-and-cat care education from a veterinary assistant.

## Current flow

1. A client opens the website, chooses a $10 Quick Question, $15 Detailed Guidance, $25 Phone Support, or Free Community Support option, enters the question, and may upload up to four files of any type at 10 MB each.
2. A secured Cloudflare Worker saves the question to the CloudKit `Question` record type. Files go to a private R2 bucket through signed links that expire after 30 days.
3. The operator receives a new-question CloudKit push notification and opens the matching question in the iPhone app. Tap Reply in Care Line to respond; the client reads and replies on their private website page. Clients must bookmark that page and return to check for replies.
4. Paid questions start **Awaiting approval**. The operator selects **Approve — I’m Available** or **Decline — Unavailable** in the question. Only after approval can the client open PayPal or Apple Pay checkout from the same private conversation page. Declining archives the request without payment. Free Community Support skips payment. The operator can see the chosen service and payment status in the app.
5. PayPal and Apple Pay update payment and refund status automatically. No operator payment messages or manual payment marking are required.
6. The operator replies on your private conversation page or by phone, marks the question answered, and may archive it.

## Main files

- `index.html`: public intake website.
- `privacy.html`: client privacy notice.
- `terms.html`: service, cancellation, and refund terms.
- `relay/cloudkit-worker.js`: CloudKit intake, abuse controls, and private attachment delivery.
- `VetAssistantHelpLine/`: private SwiftUI operator app.
- `docs/LEGAL_SCOPE.md`: response boundaries.
- `docs/SOLO_WORKFLOW.md`: daily workflow.
- `docs/PAYMENTS_SETUP.md`: automatic PayPal and Apple Pay payment process.

## Service boundary

The care line provides general educational information only. It is not veterinary medical advice, diagnosis, prognosis, prescription, medication dosing, or treatment, and it does not establish a veterinarian-client-patient relationship. Possible emergencies must be directed immediately to a licensed veterinarian or emergency hospital.

Veterinary practice and consumer rules vary by jurisdiction. Review the service, pricing, privacy notice, and terms with qualified local professionals before accepting paying clients.

## Development

Open `VetAssistantHelpLine.xcodeproj` in Xcode. The app uses the CloudKit container `iCloud.com.jmal9767.VetAssistantHelpLine`. Development and Production CloudKit schemas are separate; deploy and verify the Production schema before using TestFlight or App Store distribution.

The client site is hosted at `https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/` and posts to the configured Cloudflare Worker.
