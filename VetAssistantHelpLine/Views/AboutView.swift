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
