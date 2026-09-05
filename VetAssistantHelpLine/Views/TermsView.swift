import SwiftUI

struct TermsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Effective September 5, 2026")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let url = HelplineConfig.termsPolicyURL {
                    Link("Open the complete web Terms of Use", destination: url)
                }

                PolicySectionView(
                    title: "The service",
                    text: "\(HelplineConfig.purchaseCoverageStatement) The prepared email is addressed to \(HelplineConfig.serviceName). \(HelplineConfig.responsePromise) The response is written by a human veterinary assistant."
                )

                PolicySectionView(
                    title: "Purchase eligibility",
                    text: "You must be at least 18 years old and authorized to make the Apple in-app purchase. The app requires this confirmation before showing the purchase action. You are responsible for the information you choose to send."
                )

                PolicySectionView(
                    title: "Educational scope",
                    text: HelplineConfig.scopeStatement
                )

                PolicySectionView(
                    title: "Emergencies and medical concerns",
                    text: "Do not use or wait for this service when a pet is sick, injured, in distress, may have been poisoned, or needs diagnosis or treatment. Contact a licensed veterinarian or emergency veterinary clinic immediately."
                )

                PolicySectionView(
                    title: "Purchase and sending",
                    text: "Apple displays the localized price and may charge when you approve the purchase. Cancelling the fallback before copying the complete email preserves the verified unfinished credit for immediate reuse. Once Apple Mail displays the complete email, a saved, cancelled, failed, or unknown result remains unfinished but locked until you explicitly confirm sent or every copy deleted without sending; a copied or opened fallback is locked the same way. The app marks the credit used and finishes the transaction after Apple Mail reports the email queued or you confirm sending. Finishing records the app's email-handoff decision; it does not prove inbox receipt or human-reply delivery, and it does not defer Apple's charge. \(HelplineConfig.unusedPurchasePolicy) \(HelplineConfig.missingEmailSupportStatement) \(HelplineConfig.paidSubmissionVerificationStatement)"
                )

                PolicySectionView(
                    title: "Questions outside the service scope",
                    text: HelplineConfig.replacementQuestionPolicy
                )

                PolicySectionView(
                    title: "Refund support",
                    text: "App Store purchases are billed and managed by Apple. Contact Bay Area Apps if a question cannot be submitted or answered. Apple's purchase-support site determines whether a refund request is eligible under Apple's policies."
                )

                if let url = HelplineConfig.applePurchaseSupportURL {
                    Link("Open Apple purchase support", destination: url)
                }

                PolicySectionView(
                    title: "Acceptable use",
                    text: "Do not misuse the service, send unlawful or abusive content, impersonate another person, interfere with security or operation, attempt unauthorized access, automate excessive messages, or use educational responses to provide unlicensed veterinary services to others."
                )

                PolicySectionView(
                    title: "Email communications",
                    text: "If you send a question or contact support, you authorize Bay Area Apps to reply to the email address you use. Email is not an emergency channel and is not monitored continuously. Do not send unnecessary sensitive information."
                )

                PolicySectionView(
                    title: "Ownership",
                    text: "The app, website, branding, and original service content are owned by Bay Area Apps LLC or its licensors and are protected by applicable intellectual-property laws. You receive a limited, personal, nonexclusive, nontransferable, revocable right to use the service under these terms."
                )

                PolicySectionView(
                    title: "Service disclaimer",
                    text: "To the extent permitted by law, the service is provided as is and as available. Bay Area Apps does not warrant uninterrupted availability, compatibility with every device or email provider, or that general educational information will fit every animal or circumstance. Rely on a licensed veterinarian for medical decisions."
                )

                PolicySectionView(
                    title: "Limitation of liability",
                    text: "To the extent permitted by law, Bay Area Apps LLC will not be liable for indirect, incidental, special, consequential, or punitive damages arising from use of or inability to use the service. Nothing excludes liability that cannot lawfully be excluded or limits consumer-protection rights that apply to you."
                )

                PolicySectionView(
                    title: "Apple",
                    text: "Apple provides the App Store and StoreKit payment platform but does not provide this education service. Your use of Apple services remains subject to Apple's terms."
                )

                PolicySectionView(
                    title: "Changes and governing law",
                    text: "Bay Area Apps may update these terms when the service or legal requirements change. The effective date identifies the current version. California law governs these terms without limiting consumer protections that apply where you live."
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
        .navigationTitle("Terms Summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TermsView()
    }
}
