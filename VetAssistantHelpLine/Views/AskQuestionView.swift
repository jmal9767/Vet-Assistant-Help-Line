import MessageUI
import SwiftUI

struct AskQuestionView: View {
    @EnvironmentObject private var purchaseStore: PurchaseStore
    @StateObject private var model = QuestionFlowModel()

    @State private var preparedEmail: QuestionEmail?
    @State private var preparedCredit: PaidQuestionCredit?
    @State private var showMailComposer = false
    @State private var showMailFallback = false
    @State private var completionKind: EmailCompletionKind = .appleMailQueued
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            stepContent
                .navigationTitle(
                    purchaseStore.unresolvedHandoffCredit == nil
                        ? model.step.title
                        : "Resolve Previous Email"
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if model.step.allowsBackNavigation,
                       purchaseStore.unresolvedHandoffCredit == nil,
                       purchaseStore.state != .finishing {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                model.goBack()
                            } label: {
                                Label("Back", systemImage: "chevron.left")
                            }
                        }
                    }
                }
                .alert(HelplineConfig.serviceName, isPresented: $showAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(alertMessage)
                }
                .sheet(isPresented: $showMailComposer) {
                    if let preparedEmail {
                        MailComposerView(
                            isPresented: $showMailComposer,
                            message: preparedEmail,
                            onFinish: handleMailResult
                        )
                        .ignoresSafeArea()
                    }
                }
                .sheet(isPresented: $showMailFallback) {
                    if let preparedEmail {
                        MailFallbackView(
                            message: preparedEmail,
                            onConfirmSent: confirmFallbackEmailSent,
                            onCancel: handleFallbackCancel
                        )
                        .interactiveDismissDisabled()
                    }
                }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        if purchaseStore.state == .finishing {
            ContentUnavailableView {
                Label("Finalizing email handoff", systemImage: "envelope.badge.shield.half.filled")
            } description: {
                Text("The app is recording the email-handoff decision with StoreKit. Do not purchase again or close the app while this completes.")
            }
        } else if let credit = purchaseStore.unresolvedHandoffCredit {
            EmailHandoffRecoveryView(
                credit: credit,
                onConfirmSent: { reconcileHandoffAsSent(credit) },
                onConfirmDeleted: { reconcileHandoffAsDeleted(credit) }
            )
        } else {
            switch model.step {
            case .safety:
                SafetyScopeView(model: model) {
                    model.continueFromSafety()
                }

            case .category:
                CategorySelectionView(model: model) {
                    model.continueFromCategory()
                }

            case .details:
                QuestionDetailsView(model: model) {
                    model.continueFromDetails()
                }

            case .review:
                QuestionReviewView(model: model) {
                    model.continueFromReview()
                }

            case .purchase:
                PurchaseQuestionView(purchaseStore: purchaseStore) {
                    purchaseOrUseCredit()
                }

            case .sent:
                QuestionSentView(
                    completionKind: completionKind,
                    transactionReference: purchaseStore.lastCompletedTransactionReference
                ) {
                    clearPreparedMessage()
                    model.startAnotherQuestion()
                }
            }
        }
    }

    private func purchaseOrUseCredit() {
        if let credit = purchaseStore.currentCredit {
            prepareEmail(using: credit)
            return
        }

        Task {
            let outcome = await purchaseStore.purchaseQuestionCredit(
                appAccountToken: model.draft.id
            )
            switch outcome {
            case .verified(let credit):
                prepareEmail(using: credit)

            case .pending:
                presentAlert(
                    "Apple is waiting for purchase approval. Your question remains here, and no email can be sent until Apple verifies the purchase."
                )

            case .cancelled:
                presentAlert("The Apple purchase was cancelled. No question credit was used.")

            case .failed(let message):
                presentAlert(message)
            }
        }
    }

    private func prepareEmail(using credit: PaidQuestionCredit) {
        guard let email = QuestionEmailBuilder.build(
            draft: model.draft,
            credit: credit
        ) else {
            presentAlert(
                "The question could not be prepared. Your paid credit is safe; go back and review the required answers."
            )
            return
        }

        guard purchaseStore.markEmailHandoffStarted(for: credit) else {
            presentAlert(
                "The email handoff could not be recorded. Your paid credit is safe; do not purchase again."
            )
            return
        }

        preparedEmail = email
        preparedCredit = credit
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            showMailFallback = true
        }
    }

    private func handleMailResult(
        _ result: MFMailComposeResult,
        _ error: Error?
    ) {
        if let error {
            presentAlert(
                "Apple Mail reported an error: \(error.localizedDescription). Because the complete email was displayed, confirm whether every copy was deleted without sending or whether it was sent before using the credit again."
            )
            return
        }

        switch result {
        case .sent:
            finishPreparedCredit(completionKind: .appleMailQueued)

        case .saved:
            presentAlert(
                "Apple Mail saved the prepared email as a draft. Before the credit can be used again, confirm whether that draft was later sent or deleted without sending."
            )

        case .cancelled:
            presentAlert(
                "Apple Mail was cancelled after displaying the complete email. Confirm that every copy was deleted without sending, or confirm that it was sent, before using the credit again."
            )

        case .failed:
            presentAlert(
                "Apple Mail reported a failure after displaying the complete email. Confirm that every copy was deleted without sending, or confirm that it was sent, before using the credit again."
            )

        @unknown default:
            presentAlert(
                "The email result could not be confirmed. Resolve whether the prepared email was sent or deleted before using the credit again."
            )
        }
    }

    private func confirmFallbackEmailSent() {
        finishPreparedCredit(completionKind: .fallbackConfirmedSent)
    }

    private func handleFallbackCancel(completeEmailWasExposed: Bool) {
        if completeEmailWasExposed {
            presentAlert(
                "The complete email was copied or opened in another app. Resolve whether it was sent or deleted before using the credit again."
            )
        } else {
            clearPreparedHandoff()
            presentAlert(
                "Email preparation was cancelled before the complete message was copied. Your paid question credit is still available."
            )
        }
    }

    private func finishPreparedCredit(completionKind: EmailCompletionKind) {
        guard let preparedCredit else {
            presentAlert(
                "The paid question credit could not be matched. Do not purchase again; contact \(HelplineConfig.recipientEmail)."
            )
            return
        }

        finishCredit(preparedCredit, completionKind: completionKind)
    }

    private func finishCredit(
        _ credit: PaidQuestionCredit,
        completionKind: EmailCompletionKind
    ) {
        guard purchaseStore.handoffIsUnresolved(for: credit) else {
            presentAlert(
                "The email handoff could not be matched. Do not purchase again; contact \(HelplineConfig.recipientEmail)."
            )
            return
        }

        guard purchaseStore.recordDelivery(for: credit) else {
            presentAlert(
                "The paid question credit could not be recorded. Do not purchase again; contact \(HelplineConfig.recipientEmail)."
            )
            return
        }

        Task {
            let finished = await purchaseStore.finishRecordedCredit(credit)
            if finished {
                self.completionKind = completionKind
                clearPreparedMessage()
                model.markSent()
            } else {
                presentAlert(
                    "The email was sent, but the Apple transaction needs support. Do not purchase again; contact \(HelplineConfig.recipientEmail)."
                )
            }
        }
    }

    private func reconcileHandoffAsSent(_ credit: PaidQuestionCredit) {
        finishCredit(credit, completionKind: .handoffReconciledAsSent)
    }

    private func reconcileHandoffAsDeleted(_ credit: PaidQuestionCredit) {
        guard purchaseStore.clearEmailHandoff(for: credit) else {
            presentAlert(
                "The previous email status could not be cleared. Do not purchase again; contact \(HelplineConfig.recipientEmail)."
            )
            return
        }

        clearPreparedMessage()
        presentAlert(
            "The saved or copied email was marked deleted without sending. The existing paid credit is available to prepare one email."
        )
    }

    private func clearPreparedHandoff() {
        guard let preparedCredit else { return }
        purchaseStore.clearEmailHandoff(for: preparedCredit)
    }

    private func clearPreparedMessage() {
        preparedEmail = nil
        preparedCredit = nil
        showMailComposer = false
        showMailFallback = false
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    AskQuestionView()
        .environmentObject(PurchaseStore())
}
