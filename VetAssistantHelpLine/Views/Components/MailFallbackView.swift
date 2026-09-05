import SwiftUI
import UIKit

struct MailFallbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let message: QuestionEmail
    let onConfirmSent: () -> Void
    let onCancel: (_ completeEmailWasExposed: Bool) -> Void

    @State private var copied = false
    @State private var copiedPasteboardChangeCount: Int?
    @State private var confirmsSent = false
    @State private var isConfirming = false
    @State private var showOpenError = false
    @State private var completeEmailWasExposed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(
                        "Apple Mail is not configured on this device.",
                        systemImage: "envelope.badge"
                    )
                    Text("Your paid question credit is safe. Copy the complete email or open another email app, send it to the address below, then return here to confirm.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section("Email details") {
                    LabeledContent("To") {
                        Text(message.recipient)
                            .textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Subject")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(message.subject)
                            .textSelection(.enabled)
                    }
                }

                Section("Prepare the email") {
                    Text("Copying places the full question and Apple-signed proof on the device's system clipboard, where another app may be able to read it under iOS permissions. The copy is local to this device and set to expire after 10 minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button {
                        copyEmail()
                    } label: {
                        Label(
                            copied ? "Email copied" : "Copy complete email",
                            systemImage: copied ? "checkmark" : "doc.on.doc"
                        )
                    }

                    Button {
                        copyEmail()
                        openInAnotherMailApp()
                    } label: {
                        Label("Copy and open email app", systemImage: "arrow.up.forward.app")
                    }

                    Text("Opening another app fills only the recipient and subject to avoid URL truncation. Paste the complete copied email into the message body. Copying or opening does not finish the credit, but it locks this handoff until you confirm sending below or later confirm that every copy was deleted without sending.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Confirm only after sending") {
                    Toggle(
                        "I sent this exact question email to \(message.recipient).",
                        isOn: $confirmsSent
                    )

                    Button("Confirm sent and use question credit") {
                        guard !isConfirming else { return }
                        isConfirming = true
                        clearCopiedEmailIfCurrent()
                        onConfirmSent()
                        dismiss()
                    }
                    .disabled(!copied || !confirmsSent || isConfirming)
                    .accessibilityHint(
                        confirmsSent
                            ? "Marks this question as sent and uses the paid question credit."
                            : "Send the email and turn on the confirmation first."
                    )
                }
            }
            .navigationTitle("Send with Another App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel(completeEmailWasExposed)
                        clearCopiedEmailIfCurrent()
                        dismiss()
                    }
                }
            }
            .alert("Couldn't open an email app", isPresented: $showOpenError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The complete email has been copied. Paste it into any email app and send it to \(message.recipient).")
            }
        }
    }

    private func copyEmail() {
        UIPasteboard.general.setItems(
            [["public.utf8-plain-text": message.clipboardText]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(10 * 60)
            ]
        )
        copiedPasteboardChangeCount = UIPasteboard.general.changeCount
        copied = true
        completeEmailWasExposed = true
    }

    private func clearCopiedEmailIfCurrent() {
        guard let copiedPasteboardChangeCount,
              UIPasteboard.general.changeCount == copiedPasteboardChangeCount else {
            return
        }
        UIPasteboard.general.items = []
        self.copiedPasteboardChangeCount = nil
        copied = false
    }

    private func openInAnotherMailApp() {
        guard let url = message.fallbackMailtoURL else {
            showOpenError = true
            return
        }

        openURL(url) { accepted in
            if !accepted {
                DispatchQueue.main.async {
                    showOpenError = true
                }
            }
        }
    }
}
