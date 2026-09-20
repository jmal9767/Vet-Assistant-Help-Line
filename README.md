# Paws & Whiskers Care Line

A private iPhone operator app and public client website for general dog-and-cat care education from a veterinary assistant.

## Current flow

1. A client opens the website, chooses email, text, or phone, enters the question, and may upload up to four files of any type at 10 MB each.
2. A secured Cloudflare Worker saves the question to the CloudKit `Question` record type. Files go to a private R2 bucket through signed links that expire after 30 days.
3. The operator receives a CloudKit push notification and opens the matching question in the iPhone app.
4. The operator chooses a $10, $20, or $35 service, complimentary service, or a no-charge referral based on the question and time needed.
5. Paid clients receive PayPal/Apple Pay checkout or a Cash App for Business link. PayPal and Apple Pay confirm in the app automatically; Cash App is confirmed manually.
6. The operator replies by email, text, or phone, marks the question answered, and may archive it.

## Main files

- `index.html`: public intake website.
- `privacy.html`: client privacy notice.
- `terms.html`: service, cancellation, and refund terms.
- `relay/cloudkit-worker.js`: CloudKit intake, abuse controls, and private attachment delivery.
- `VetAssistantHelpLine/`: private SwiftUI operator app.
- `docs/LEGAL_SCOPE.md`: response boundaries.
- `docs/SOLO_WORKFLOW.md`: daily workflow.
- `docs/PAYMENTS_SETUP.md`: complimentary, PayPal, Apple Pay, and Cash App payment process.

## Service boundary

The care line provides general educational information only. It is not veterinary medical advice, diagnosis, prognosis, prescription, medication dosing, or treatment, and it does not establish a veterinarian-client-patient relationship. Possible emergencies must be directed immediately to a licensed veterinarian or emergency hospital.

Veterinary practice and consumer rules vary by jurisdiction. Review the service, pricing, privacy notice, and terms with qualified local professionals before accepting paying clients.

## Development

Open `VetAssistantHelpLine.xcodeproj` in Xcode. The app uses the CloudKit container `iCloud.com.jmal9767.VetAssistantHelpLine`. Development and Production CloudKit schemas are separate; deploy and verify the Production schema before using TestFlight or App Store distribution.

The client site is hosted at `https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/` and posts to the configured Cloudflare Worker.
