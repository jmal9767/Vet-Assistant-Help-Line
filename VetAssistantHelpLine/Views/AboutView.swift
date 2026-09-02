import SwiftUI

struct AboutView: View {
    private let canHelp = [
        "General pet care, feeding, and husbandry questions",
        "Grooming, enrichment, and basic behavior tips",
        "Preparing for vet visits & what to ask your vet",
        "Understanding routine care basics",
        "Deciding whether something needs a veterinarian",
        "Pointing you to trusted resources"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Free general pet-care guidance from a veterinary assistant, answered within \(HelplineConfig.responseWindow).")
                        .font(.headline)
                }

                Section("What I can help with") {
                    ForEach(canHelp, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("What does it cost?") {
                    Label("This help line: $0 — always free", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text("There are no charges, ever, for asking questions here — no sign-up fees, no per-question fees, no subscriptions, and no tips. I will never email you asking for payment, card numbers, or gift cards; a message like that is not from me.")
                        .font(.callout)
                    Text("Outside services I may refer you to have their own fees (prices vary by region — always confirm when you call):\n\n• ASPCA Poison Control \(HelplineConfig.poisonControlDisplay): one-time consultation fee, currently around $95\n• Emergency vet: exam/triage fee often $100–$250 up front, treatment on top — ask for an estimate first\n• Regular checkup: exam fees commonly $50–$100, plus vaccines or tests\n• Low-cost options: humane societies, nonprofit clinics, and vet-school clinics offer reduced fees; many clinics take payment plans, CareCredit, or Scratchpay")
                        .font(.callout)
                }

                Section("What I can't do") {
                    Text("I'm a veterinary assistant, not a licensed veterinarian. I cannot diagnose conditions, prescribe or recommend medication doses, or replace an exam by your vet. When in doubt, I'll always point you to a licensed veterinarian.")
                        .font(.callout)
                }

                Section("Disclaimer") {
                    Text(HelplineConfig.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About")
        }
    }
}

#Preview {
    AboutView()
}
