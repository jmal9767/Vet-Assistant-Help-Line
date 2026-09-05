import StoreKit
import SwiftUI

struct PurchaseQuestionView: View {
    @ObservedObject var purchaseStore: PurchaseStore
    let onPurchaseOrSend: () -> Void

    @State private var showPendingResetConfirmation = false

    var body: some View {
        List {
            Section {
                Label("One paid general education submission", systemImage: "envelope.open.fill")
                    .font(.headline)
                Text("Nonmedical education by email — not monitored for emergencies")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.red)
                Text(HelplineConfig.purchaseCoverageStatement)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.responsePromise)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let credit = purchaseStore.currentCredit {
                Section("Paid credit ready") {
                    Label("You already have a verified question credit.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Composing with this credit does not start another purchase. After Apple Mail displays the complete email, every result except queued requires explicit sent-or-deleted resolution; a copied fallback does too. Cancelling fallback before copying leaves the credit immediately reusable.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    LabeledContent("Apple transaction reference") {
                        Text(String(credit.id))
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Environment", value: credit.environment)
                    Text("Use the full transaction reference—not an App Store order or receipt number—when contacting purchase support.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let product = purchaseStore.product {
                Section("Apple in-app purchase") {
                    LabeledContent("Product", value: product.displayName)
                    LabeledContent("Price", value: product.displayPrice)
                    if !product.description.isEmpty {
                        Text(product.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Text("Apple displays and processes the final localized price before you approve payment.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("What happens next") {
                Label("Apple verifies the purchase", systemImage: "1.circle.fill")
                Label("The app prepares your structured email", systemImage: "2.circle.fill")
                Label("You review and send the email", systemImage: "3.circle.fill")
                Label("A human replies by email", systemImage: "4.circle.fill")
            }

            Section("Scope before purchase") {
                Text(HelplineConfig.scopeStatement)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.replacementQuestionPolicy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.unusedPurchasePolicy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.paidSubmissionVerificationStatement)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            purchaseStatusSection

            Section {
                Button(action: onPurchaseOrSend) {
                    if purchaseStore.state == .finishing {
                        HStack {
                            ProgressView()
                            Text("Finalizing email handoff…")
                        }
                        .frame(maxWidth: .infinity)
                    } else if purchaseStore.currentCredit != nil {
                        Text("Compose question email")
                            .frame(maxWidth: .infinity)
                    } else if let price = purchaseStore.displayPrice {
                        Text("Purchase for \(price)")
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Purchase unavailable")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(purchaseButtonIsDisabled)
            } footer: {
                Text("Apple may charge when you approve the purchase. The app keeps the verified StoreKit transaction unfinished while the email handoff is unresolved. After Apple Mail displays the complete email, a saved, cancelled, failed, or uncertain result is locked against duplicate preparation; a copied or opened fallback is locked too. Confirming sent marks the credit used and finishes the transaction. Confirming every copy was deleted without sending unlocks the same unfinished credit. Finishing records the app's email-handoff decision; it does not prove inbox receipt or delivery of the human reply, and it does not defer Apple's charge.")
            }
        }
        .alert(
            "Clear the pending Apple request?",
            isPresented: $showPendingResetConfirmation
        ) {
            Button("Keep waiting", role: .cancel) {}
            Button("I confirmed it cannot complete", role: .destructive) {
                Task {
                    await purchaseStore.clearResolvedPendingPurchase()
                }
            }
        } message: {
            Text("Only clear this status after Apple or the family organizer shows that the approval request was declined or expired and cannot complete. Clearing it allows a new purchase attempt; a purchase that later completes may still be charged.")
        }
    }

    @ViewBuilder
    private var purchaseStatusSection: some View {
        switch purchaseStore.state {
        case .loading:
            Section {
                HStack {
                    ProgressView()
                    Text("Loading Apple's purchase information…")
                }
            }

        case .purchasing:
            Section {
                HStack {
                    ProgressView()
                    Text("Waiting for Apple…")
                }
            }

        case .finishing:
            Section {
                HStack {
                    ProgressView()
                    Text("Finalizing the previous email handoff…")
                }
                Text("Do not make another purchase while this completes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .handoffUnresolved:
            Section {
                Label("Previous email status needs resolution", systemImage: "envelope.badge.shield.half.filled")
                Text("Confirm whether the previously prepared email was sent or deleted before using this credit again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

        case .pending:
            Section {
                Label("Purchase approval is pending", systemImage: "clock.fill")
                Text("No question can be sent until Apple approves and verifies the purchase. You can return later; the app will continue listening for the matching result. Do not start another purchase while approval is unresolved; check the Apple or family-organizer status if it does not update.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let url = HelplineConfig.contactEmailURL {
                    Link("Contact free purchase support", destination: url)
                }
                Button("I confirmed the request cannot complete") {
                    showPendingResetConfirmation = true
                }
            }

        case .verificationFailed(let message):
            Section {
                Label(message, systemImage: "exclamationmark.shield.fill")
                    .foregroundStyle(.red)
                Text("Your question remains unsent. Email \(HelplineConfig.recipientEmail) for purchase help; do not make another purchase until this is resolved.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Retry Apple transaction verification") {
                    Task {
                        await purchaseStore.retryTransactionRecovery()
                    }
                }
            }

        case .unavailable(let message):
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Retry Apple purchase information") {
                    Task {
                        await purchaseStore.reloadProduct()
                    }
                }
            }

        case .ready:
            EmptyView()
        }
    }

    private var purchaseButtonIsDisabled: Bool {
        if purchaseStore.state == .finishing || purchaseStore.state == .handoffUnresolved {
            return true
        }

        if purchaseStore.currentCredit != nil {
            return false
        }

        switch purchaseStore.state {
        case .ready:
            return purchaseStore.product == nil
        case .loading, .purchasing, .finishing, .handoffUnresolved, .pending, .verificationFailed, .unavailable:
            return true
        }
    }
}
