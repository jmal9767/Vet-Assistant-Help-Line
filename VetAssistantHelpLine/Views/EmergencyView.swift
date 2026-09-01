import SwiftUI

struct EmergencyView: View {
    private let redFlags = [
        "Difficulty breathing",
        "Seizures or collapse",
        "Suspected poisoning",
        "Hit by a car / major trauma",
        "Bloated or swollen belly, unproductive retching",
        "Unable to urinate (especially male cats)",
        "Pale or blue gums",
        "Uncontrolled bleeding",
        "Heatstroke symptoms",
        "Eye injury",
        "Prolonged labor / birthing trouble",
        "Snake or spider bite"
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("If your pet has any of these signs, contact an emergency veterinarian immediately — don't wait for a help-line reply.")
                        .font(.headline)
                        .foregroundStyle(.red)
                        .listRowBackground(Color.red.opacity(0.1))
                }

                Section("Red-flag signs") {
                    ForEach(redFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Get help now") {
                    Link(destination: HelplineConfig.emergencyVetLocatorURL) {
                        Label("Find an emergency vet near you", systemImage: "cross.case.fill")
                    }
                    Link(destination: URL(string: "tel:\(HelplineConfig.poisonControlNumber)")!) {
                        Label("Poison Control \(HelplineConfig.poisonControlDisplay)", systemImage: "phone.fill")
                    }
                    Text("ASPCA Animal Poison Control is available 24/7. A consultation fee may apply.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Emergency?")
        }
    }
}

#Preview {
    EmergencyView()
}
