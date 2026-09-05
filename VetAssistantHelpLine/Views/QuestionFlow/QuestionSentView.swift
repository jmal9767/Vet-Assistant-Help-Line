import SwiftUI

struct QuestionSentView: View {
    let completionKind: EmailCompletionKind
    let transactionReference: String?
    let onStartAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                Text(completionTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(completionDetail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(HelplineConfig.responsePromise)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text("Check the email account you sent from for the human reply. If your pet develops a medical concern while you wait, contact a licensed veterinarian instead of waiting for email.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(HelplineConfig.missingEmailSupportStatement)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let transactionReference {
                    VStack(spacing: 4) {
                        Text("Apple transaction reference")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(transactionReference)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let url = HelplineConfig.contactEmailURL {
                    Link("Contact free purchase support", destination: url)
                }

                Button("Start another paid question", action: onStartAnother)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: 560)
            .padding(28)
        }
    }

    private var completionTitle: String {
        switch completionKind {
        case .appleMailQueued:
            "Apple Mail queued your question"
        case .fallbackConfirmedSent:
            "You confirmed your question was sent"
        case .handoffReconciledAsSent:
            "You confirmed the prepared email was sent"
        }
    }

    private var completionDetail: String {
        switch completionKind {
        case .appleMailQueued:
            "Apple Mail's sent result means the message was placed in its outbox; it does not guarantee delivery."
        case .fallbackConfirmedSent:
            "The app marked the question credit used based on your explicit confirmation."
        case .handoffReconciledAsSent:
            "The app marked the question credit used after you resolved the earlier uncertain email handoff."
        }
    }
}
