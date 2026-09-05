import SwiftUI

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Effective September 5, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let url = HelplineConfig.privacyPolicyURL {
                    Link("Open the web Privacy Policy", destination: url)
                }

                PolicySectionView(
                    title: "Information you provide",
                    text: "The question form asks you to choose a category and enter one general question. The prepared email also includes the StoreKit-bound submission reference, Apple transaction reference, environment, and Apple's signed transaction proof. That proof can contain product, purchase-time, price, currency, storefront, transaction, app-account-token, environment, and related App Store metadata. The form does not ask for a name or pet details, but a sent email can include your sender email address and display name if supplied by your mail provider. \(HelplineConfig.questionDataWarning) Do not send street addresses or other unnecessary sensitive information."
                )

                PolicySectionView(
                    title: "Public website",
                    text: "The website has no question form, account, advertising, analytics, or tracking code, and its own code does not set cookies. Infrastructure used to deliver and secure the site may receive ordinary connection data, such as IP address, browser type, requested page, and access time, and handles it under the provider's terms and retention practices."
                )

                PolicySectionView(
                    title: "How information is sent",
                    text: "The app does not have an account system or submission server. Your draft question is not intentionally sent to Bay Area Apps until you send the prepared email to \(HelplineConfig.recipientEmail). Opening a mail composer first shares the prepared content with the device's mail service, even if you later cancel; that provider handles it under its own terms. Opening Apple, Maps, telephone, license-lookup, or other external links may disclose ordinary connection or call metadata to those providers under their own terms."
                )

                PolicySectionView(
                    title: "Purchases",
                    text: "Apple processes the in-app purchase. The app checks Apple's signed transaction result and keeps an unfinished verified transaction as a question credit until the email is reported or confirmed as sent. Before accepting a message as a new paid question, Bay Area Apps verifies the signed proof and current transaction state with Apple's official server tools, then atomically records keyed hashes so that transaction cannot be accepted twice. If verification is temporarily unavailable and a message includes an unexpected attachment that must be deleted, Bay Area Apps may extract only the exact signed JWS into a random-reference, proof-only temporary file on an encrypted operator volume. That file contains no sender address, question, subject, attachment, or other message content; it is owner-only, excluded from backup and synchronization, retained only during the unresolved payment hold, and deleted immediately after a definitive result. Bay Area Apps does not receive your payment-card information."
                )

                PolicySectionView(
                    title: "On-device handling",
                    text: "Draft question text is held in the app while you complete the flow and is not intentionally uploaded to Bay Area Apps before you send the email. The app stores limited purchase and email-handoff state on the device so an unfinished verified credit is not lost, silently duplicated after Apple Mail displays it or a fallback is copied, or reused after a confirmed send. Pending-purchase state remains until resolved. To protect against reuse after an App Store account change or interrupted finish, transaction-ID handoff/use markers may remain until the relevant handoff is resolved or the app's data is removed. The last used transaction reference remains readable for purchase support for 90 days and its stored keys are removed on the next app launch after expiry. A fallback copy places the full question and Apple-signed proof on the device's system clipboard, where another app may be able to read it under iOS permissions. It is marked local to this device, set to expire after 10 minutes, and cleared on confirmation or cancellation when it has not already been replaced."
                )

                PolicySectionView(
                    title: "Email use and deletion",
                    text: "Bay Area Apps uses a submitted email to verify one paid redemption, provide the requested human response, and handle support. It is not sold or used for advertising. Operator-controlled question, answer, and ordinary support correspondence is deleted or de-identified 90 days after the final response or closure, whichever applies. A thread with an offered replacement is kept through its stated deadline; if no timely replacement arrives, that deadline is its closure date and the thread is deleted or de-identified 90 days later. If a timely replacement arrives, its correspondence is kept until 90 days after its final response or closure. The separate redemption ledger never stores email or question content; it keeps keyed hashes of verified transaction and submission references, environment, and redemption time for the life of the paid service to prevent replay, then deletes them within 90 days after the service truly ends. The service is not treated as ended until sales stop and device credits not marked sent, signed proofs awaiting reconciliation, payment holds, paid messages already handed off, open questions, disputes, and replacement windows are honored or otherwise resolved. Limited records may be kept longer only for a documented, time-bounded legal, security, dispute, fraud, accounting, or transaction need. To request deletion, contact the address below from the email account that sent the question."
                )

                PolicySectionView(
                    title: "Service providers and disclosure",
                    text: "Apple handles StoreKit purchases. Email and website providers deliver messages and pages. Bay Area Apps does not sell personal information or disclose it for cross-context behavioral advertising. Bay Area Apps requires providers it selects to protect information consistently with this policy and use it only for the contracted service. Bay Area Apps configures retention settings it controls to follow this policy; provider backups, quarantine, and security records may remain for limited contractual schedules. A mail provider independently chosen by you is governed by your agreement with that provider. Information may also be disclosed when reasonably necessary to comply with law, protect rights or safety, investigate fraud or abuse, or answer a valid legal request."
                )

                PolicySectionView(
                    title: "Security",
                    text: "Bay Area Apps uses reasonable administrative and technical safeguards appropriate to the information handled. No website, device, email system, or storage method can be guaranteed completely secure. Send only the information needed for your request."
                )

                PolicySectionView(
                    title: "Your choices",
                    text: "You may ask to access, correct, or delete correspondence Bay Area Apps controls. StoreKit billing, purchase-history, and refund requests may need to be handled by Apple. Minimal keyed redemption hashes may be retained for replay prevention even after message deletion because removing them would allow the same purchase proof to be reused."
                )

                PolicySectionView(
                    title: "Children",
                    text: "The paid service is only for adults age 18 or older and is not directed to children. Bay Area Apps does not knowingly collect personal information from children. Contact Bay Area Apps if you believe a child provided information."
                )

                PolicySectionView(
                    title: "External services and changes",
                    text: "Apple, Maps, emergency-veterinary resources, telephone services, license lookup, and other external services have their own policies. Bay Area Apps may update this policy when the service or legal requirements change; the effective date identifies the current version."
                )

                PolicySectionView(
                    title: "Tracking",
                    text: "The native app does not include advertising, third-party analytics, or cross-app tracking."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Contact")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let url = HelplineConfig.contactEmailURL {
                        Link(HelplineConfig.recipientEmail, destination: url)
                    } else {
                        Text(HelplineConfig.recipientEmail)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyView()
    }
}
