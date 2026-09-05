import SwiftUI

struct EmailHandoffRecoveryView: View {
    let credit: PaidQuestionCredit
    let onConfirmSent: () -> Void
    let onConfirmDeleted: () -> Void

    @State private var confirmation: Confirmation?

    var body: some View {
        List {
            Section {
                Label("Resolve the previous prepared email", systemImage: "envelope.badge.shield.half.filled")
                    .font(.headline)
                Text("The complete paid email was displayed in Apple Mail or copied for another email app and may still exist. To prevent a duplicate submission, the app will not prepare another email or start another purchase until you resolve what happened.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Choose what actually happened") {
                Button("I sent the prepared email") {
                    confirmation = .sent
                }
                Button("I deleted it without sending") {
                    confirmation = .deleted
                }
            }

            Section("Purchase reference") {
                Text(String(credit.id))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Text("If neither choice is accurate, do not purchase again. Contact \(HelplineConfig.recipientEmail) for free purchase support.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = HelplineConfig.contactEmailURL {
                    Link("Contact purchase support", destination: url)
                }
            }
        }
        .alert(
            confirmation?.title ?? "Resolve email",
            isPresented: Binding(
                get: { confirmation != nil },
                set: { if !$0 { confirmation = nil } }
            ),
            presenting: confirmation
        ) { choice in
            Button("Go back", role: .cancel) {}
            Button(choice.actionTitle, role: choice == .deleted ? .destructive : nil) {
                confirmation = nil
                switch choice {
                case .sent:
                    onConfirmSent()
                case .deleted:
                    onConfirmDeleted()
                }
            }
        } message: { choice in
            Text(choice.message)
        }
    }

    private enum Confirmation: Equatable {
        case sent
        case deleted

        var title: String {
            switch self {
            case .sent: "Confirm the email was sent?"
            case .deleted: "Confirm the email was deleted?"
            }
        }

        var actionTitle: String {
            switch self {
            case .sent: "Confirm sent"
            case .deleted: "Confirm deleted"
            }
        }

        var message: String {
            switch self {
            case .sent:
                "This permanently uses the paid question credit. A queued or sent message still may fail to reach the inbox."
            case .deleted:
                "Choose this only if every saved draft and copied message was deleted without being sent. The existing credit will become available to prepare one email again."
            }
        }
    }
}
