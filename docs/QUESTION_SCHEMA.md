# CloudKit connection status

Last verified: 2026-09-20. Website submissions reach CloudKit, the operator account is assigned, and phone notifications have been received.

## Accounts and project

- Apple Developer team: **Bay Area Apps LLC — XF8WR8DG9P**.
- Xcode Apple Accounts confirms **info@bayareaapps.com** has Admin access to Bay Area Apps LLC.
- The other Apple team, **Jahmal Parris — 5897B74AR4**, showed no CloudKit containers. Do not change the app to that team.
- Container: `iCloud.com.jmal9767.VetAssistantHelpLine`.
- Database/environment: **Public / Development**. Production has not been changed.
- The actual project open in Xcode is `/Users/jp/Desktop/CritterCare Github/Vet-Assistant-Help-Line`. It has existing uncommitted user edits; preserve them.
- Deployment work is in the separate checkout `/Users/jp/Documents/New project/Vet-Assistant-Help-Line`.

## Completed

- Created Question with all 21 String fields and submittedAt Date/Time.
- Created recordName Queryable and submittedAt Queryable/Sortable indexes.
- World and Authenticated have no Question permissions. Creator retains Write.
- Created Operator with Read and Write on Question and assigned the operator iCloud user.
- Created Relay with Create, Read, and Write access on Question and assigned it only to the private server-to-server identity. The Worker uses Read to validate question-specific checkout details and Write for verified payment-status updates.
- Registered the Development server key named Vet Helpline Development Relay.
- Authorized Wrangler and deployed `vet-helpline-development` with CloudKit credentials stored as Worker secrets.
- Worker URL: https://vet-helpline-development.dkjmmz6whh.workers.dev
- Verified deployed Worker version: `d0badf97-c264-4b59-a69d-6e1dde609e70`.
- Local checks passed for multipart intake, 22-field mapping, cryptographic request signature, CORS, validation, payment defaults, and rejection of unconfigured file uploads/webhooks. Wrangler dry-run passed.
- A fictional multipart submission returned HTTP 200 and was verified in CloudKit as a new Question with all expected values.
- Published Worker URL `https://vet-helpline-development.dkjmmz6whh.workers.dev` to the GitHub Pages website in commit `ee7a70f`; the Pages deployment completed successfully.

## Live test results and remaining work

The server-side intake path and phone notifications are working. PayPal live credentials, Apple Pay domain onboarding, and Cloudflare R2 storage still require their provider account setup. Do not grant World or all authenticated iCloud users access to client records.

The connected iPhone is running iOS 27 beta, while the installed Xcode 26.6 cannot mount its developer disk image. A compatible Xcode version is required to install and debug this build directly on that phone.

## Required fields for the current app

All fields below are String except submittedAt, which is Date/Time (Web Services TIMESTAMP):

| Existing in Development | Still required by the newer app |
| --- | --- |
| name | preferredReply |
| email | requestedService |
| phone | petName |
| species | urgency |
| age | attachmentSummary |
| category | sourceChannel |
| question | conversationStatus |
| status | paymentStatus |
| submittedAt (Date/Time) | paymentMethod |
| | paymentAmount |
| | paymentLink |
| | signedConsentName |
| | signedConsentAt |

signedConsentAt is a String containing an ISO timestamp; it is not a Date/Time field in the current app. The relay sets status to new and submittedAt to the current time. New submissions always start with paymentStatus Unpaid.

The reference in ../cloudkit/Question.ckdb describes the target Question schema only. It is not a complete container export and has not been imported or validated using cktool. Merge with a complete schema export before any import; do not replace the container schema with this partial file.

Attachment storage, email/SMS providers, and Production deployment remain unconfigured. Submissions containing file attachments are explicitly rejected until storage is connected; files are not silently discarded.
