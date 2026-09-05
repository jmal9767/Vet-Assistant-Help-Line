# Veterinary Assistant Help Line

Veterinary Assistant Help Line is an iOS app from Bay Area Apps LLC for paid,
human-written pet-care education. Pet owners complete a safety screen, choose
a permitted nonmedical category, answer one category-specific prompt, review the
request, and purchase one question credit through Apple before preparing and sending a
structured email to the operator.

The app does not use AI and does not provide veterinary medical advice. The
emergency and out-of-scope routes are always available without a purchase.

## Product boundary

- One consumable in-app purchase unlocks one general-education question email
  for human scope review; an eligible question receives one educational answer.
- Apple supplies the localized price shown in the app.
- Questions are sent to `info@bayareaapps.com` through the device's email
  system.
- A valid paid email or authorized replacement normally receives a human answer
  or scope/referral notice by 5:00 p.m. Pacific Time on the second business day
  after actual inbox receipt. The first business day after receipt is day one;
  weekends and U.S. federal holidays do not count, and there is no 5:00 p.m.
  receipt cutoff or rollover. This is a target, not a guarantee.
- Medical concerns, medication or dosing questions, diagnosis, treatment,
  prognosis, urgency decisions, and interpretation of photos, records, tests,
  or imaging are not accepted.
- There is no live consultation, subscription, public operator portal, web
  intake form, OpenAI integration, account, or question-content database. A
  minimal operator redemption ledger stores only keyed reference hashes,
  environment, and redemption time to prevent purchase replay.

## Customer flow

1. Read the free emergency and scope screen.
2. Confirm the question is not about a sick, injured, painful, post-operative,
   pregnant, or possibly poisoned animal.
3. Choose one of the four safe education categories.
4. Use the category-specific prompt and example to write one general question.
5. Review the request and confirm the response target, purchase lifecycle, and
   18+ purchase authorization.
6. Complete the verified Apple in-app purchase, or use an unfinished verified
   credit from an interrupted attempt.
7. Review and send the structured email. Cancelling fallback before copying the
   complete message leaves the unfinished credit immediately reusable. Once Apple
   Mail displays the complete email, a saved, cancelled, failed, or unknown result
   locks it until the client confirms sent or every copy deleted without sending;
   a copied or opened fallback is locked the same way. Apple Mail's sent result
   means queued, not guaranteed delivered.
8. The operator verifies the emailed Apple signature and fresh Production
   transaction status, then atomically redeems the transaction once before
   accepting the email as a paid initial question.

## Repository map

| Path | Purpose |
|---|---|
| `VetAssistantHelpLine/` | SwiftUI app, typed intake models, StoreKit service, email composer, emergency actions, and in-app policies |
| `VetAssistantHelpLineTests/` | Unit tests for categories, validation, and structured email generation |
| `VetAssistantHelpLine.xcodeproj/` | Xcode project and shared build/test scheme |
| `.github/workflows/` | macOS iOS build/test checks and repository validation |
| `index.html` | Public marketing, support, and emergency landing page; it never accepts questions or payment |
| `privacy.html`, `terms.html` | Public policy pages for App Store metadata |
| `sw.js` | Temporary retirement worker that removes the obsolete PWA cache and unregisters itself; the current site never registers it |
| `docs/LEGAL_SCOPE.md` | Operator scope rules and California source links |
| `docs/RESPONSE_TEMPLATES.md` | Conservative human-response templates |
| `docs/SOLO_WORKFLOW.md` | Daily operator and escalation workflow |
| `operator/` | Apple-signed transaction verification and atomic one-use redemption ledger |

## Open and test

Requirements: Xcode 16 or later and an iOS 17 or later simulator/device.

1. Open `VetAssistantHelpLine.xcodeproj`.
2. Select the shared `VetAssistantHelpLine` scheme.
3. For local purchase testing, confirm the scheme uses
   `VetAssistantHelpLine/Configuration/VetAssistantHelpLine.storekit`.
4. Run the app and use Xcode's StoreKit transaction manager to test success,
   cancellation, pending approval, interruption, and unfinished-credit
   recovery.
5. Run the `VetAssistantHelpLineTests` test target.

Command-line verification on macOS:

```sh
xcodebuild \
  -project VetAssistantHelpLine.xcodeproj \
  -scheme VetAssistantHelpLine \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest' \
  clean test CODE_SIGNING_ALLOWED=NO
```

## App Store Connect setup

Before TestFlight or App Store submission:

1. Set the development team in Signing & Capabilities and confirm the included
   In-App Purchase capability.
2. Register the bundle identifier
   `com.bayareaapps.vetassistanthelpline`.
3. Create a **Consumable** in-app purchase with product identifier
   `com.bayareaapps.vetassistanthelpline.education_question`.
4. Match the App Store Connect product name and short display description to the
   local StoreKit configuration (`One nonmedical education question email.`),
   select the live price, and put the complete timing, scope, email-handoff, and
   replacement disclosure adjacent to the purchase and in the listing/review notes.
5. Complete the Paid Apps agreement, tax, and banking setup.
6. Deploy only `index.html`, `privacy.html`, `terms.html`, `site.css`, and—only
   during an old-PWA migration—the temporary `sw.js`. Never publish the repository
   root, app source, StoreKit configuration, tests, `docs/`, or `operator/`.
   Host the public files at the stable branded path used by the app, including
   `https://bayareaapps.com/veterinary-assistant-help-line/privacy.html`, and
   use the landing page as the App Store Connect Support URL. Confirm both URLs
   return HTTP 200 without authentication on a physical device. Use a CDN, proxy,
   or host that can send HSTS, `X-Content-Type-Options: nosniff`, a restrictive
   `frame-ancestors` directive, Referrer-Policy, and Permissions-Policy; do not
   assume a repository-only GitHub Pages deployment can set those response headers.
   Verify direct requests for `/operator/`, `/docs/`, source, tests, and `.storekit`
   files return 404, and verify actual log, cookie, subprocessor, and retention
   behavior against the published privacy policy.
   If the former GitHub Pages/PWA origin was ever live, first deploy the included
   `sw.js` at that same origin and scope with `Cache-Control: no-cache`; verify on
   a browser that previously installed `vahl-v1` that obsolete cached intake and
   operator pages disappear and the worker unregisters. Remove the retirement
   file only after that migration is complete.
7. Complete App Privacy answers for name, email address, emails/messages, other
   user content, and purchase history as linked, nontracking data used for App
   Functionality. Keep the included privacy manifest aligned with any future
   required-reason API use.
8. Configure the operator verifier with Apple's current root certificates, the
   App Apple ID, protected App Store Server API credentials, a separately stored
   HMAC key, and an encrypted production ledger. Test archived-proof verification,
   fresh current-status lookup, revocation rejection, unavailable/retry handling,
   key/environment metadata mismatch, and replay rejection. Use completely separate
   Production and Sandbox ledgers and HMAC keys. Validate an aged signed-proof fixture
   before launch so non-expiring credits remain verifiable without weakening the
   fresh server proof.
9. Configure and verify SPF, DKIM, DMARC, TLS delivery, MFA, recovery, and
   forwarding-rule alerts for the service mailbox and domain.
   Enable GitHub secret scanning and push protection where the repository plan
   supports them, and review the full repository history for old credentials
   before making the code public.
10. Add App Review notes explaining the free emergency route, the pre-purchase
    scope screen, the consumable question credit, and how reviewers can test it.
    Pair the app name with “Nonmedical education by email — not monitored for
    emergencies” in the App Store listing and adjacent purchase disclosure. Before
    enabling sales, obtain App Review treatment for the payment model and the
    email-app dependency using a reviewable build and complete notes; do not assume
    an asynchronous answer delivered outside the app will be classified as an
    in-app digital service. If App Review treats it as an outside-app service,
    rejects the external-mail dependency, or finds the app below minimum utility,
    keep sales disabled and revise the payment/submission architecture before
    release rather than changing only metadata.
11. Test the live product in Sandbox and TestFlight on a physical device.
12. Generate Xcode's archive Privacy Report, reconcile it with the privacy
   manifest and App Store Connect answers, then run Organizer validation.
13. Document a wind-down plan before sales begin: stop new sales first, keep the
    mailbox, verifier, and ledger available, honor device credits not marked sent,
    reconcile signed proofs and every paid message already handed off, resolve
    payment holds and disputes, honor every open replacement window, and support
    Apple refund resolution
    before treating the paid service as ended.

The repository deliberately leaves `DEVELOPMENT_TEAM` unset because Apple
team identifiers are account-specific. The code should not be described as
released or production-verified until signed Xcode builds, StoreKit Sandbox
tests, operator verification, policy hosting, and App Review configuration are
complete.

## Operating documents

Read [Legal Scope](docs/LEGAL_SCOPE.md), [Response
Templates](docs/RESPONSE_TEMPLATES.md), and [Solo
Workflow](docs/SOLO_WORKFLOW.md) before accepting customer questions.

## Support

Bay Area Apps LLC — `info@bayareaapps.com`
