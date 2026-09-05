import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var purchaseStore: PurchaseStore

    var body: some View {
        List {
            Section {
                Label(HelplineConfig.serviceName, systemImage: "pawprint.fill")
                    .font(.headline)
                Text("Nonmedical education by email — not monitored for emergencies")
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.responsePromise)
                    .font(.callout.weight(.semibold))
            }

            Section("One-question service") {
                if let product = purchaseStore.product {
                    LabeledContent("Apple price", value: product.displayPrice)
                    Text(product.displayName)
                        .font(.callout)
                } else {
                    LabeledContent("Price", value: "Shown by Apple")
                }

                Text(HelplineConfig.purchaseCoverageStatement)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(HelplineConfig.replacementQuestionPolicy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Eligible topics") {
                ForEach(QuestionCategory.allCases) { category in
                    Label(category.title, systemImage: "checkmark.circle.fill")
                }
            }

            Section("Free provider & cost guidance") {
                Text(HelplineConfig.freeProviderAndCostGuidance)
                    .font(.callout)
                if let url = HelplineConfig.emergencyVetLocatorURL {
                    Link("Search Maps for veterinary providers", destination: url)
                }
                if let url = HelplineConfig.californiaVeterinaryLicenseLookupURL {
                    Link("Verify a California veterinary license", destination: url)
                }
                Text("For a sick, injured, or distressed pet, contact a veterinarian now and do not wait while comparing costs.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Professional boundary") {
                Text(HelplineConfig.scopeStatement)
                    .font(.callout)
                Text("Emergency contacts and the service's medical-scope restrictions appear before any category or purchase is shown.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Policies") {
                NavigationLink("Privacy") {
                    PrivacyView()
                }
                NavigationLink("Terms") {
                    TermsView()
                }
            }

            Section("Free service & purchase support") {
                Text("Questions about how the service, email process, or Apple purchase works do not require a paid submission.")
                    .font(.callout)
                if let url = HelplineConfig.contactEmailURL {
                    Link(HelplineConfig.recipientEmail, destination: url)
                } else {
                    Text(HelplineConfig.recipientEmail)
                        .textSelection(.enabled)
                }
                if let reference = purchaseStore.lastCompletedTransactionReference {
                    LabeledContent("Last used Apple transaction") {
                        Text(reference)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    Text("Readable on this device for 90 days for purchase and missing-email support; removed on the next app launch after expiry.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("About")
    }
}

#Preview {
    NavigationStack {
        AboutView()
            .environmentObject(PurchaseStore())
    }
}
