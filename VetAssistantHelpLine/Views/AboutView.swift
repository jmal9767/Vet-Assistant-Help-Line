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

                Section("Services & pricing") {
                    ForEach(HelplineConfig.serviceTiers, id: \.name) { tier in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(tier.name).font(.headline)
                                Spacer()
                                Text(tier.price)
                                    .font(.headline)
                                    .foregroundStyle(tier.price == "Free" ? Color.green : Color.accentColor)
                            }
                            Text(tier.details)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    Text("Nothing is charged up front — paid tiers are confirmed with you by email before any work starts, and payment is arranged by the method that suits you. If your question is really one for a licensed veterinarian, I'll tell you that for free. I will never ask for gift cards, wire transfers, or card numbers.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Outside costs to know about") {
                    Text("Services I may refer you to have their own fees (prices vary by region — always confirm when you call):\n\n• ASPCA Poison Control \(HelplineConfig.poisonControlDisplay): one-time consultation fee, currently around $95\n• Emergency vet: exam/triage fee often $100–$250 up front, treatment on top — ask for an estimate first\n• Regular checkup: exam fees commonly $50–$100, plus vaccines or tests\n• Low-cost options: humane societies, nonprofit clinics, and vet-school clinics offer reduced fees; many clinics take payment plans, CareCredit, or Scratchpay")
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
