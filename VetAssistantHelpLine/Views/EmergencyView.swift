import SwiftUI
import UIKit

struct EmergencyView: View {
    @Environment(\.openURL) private var openURL

    @State private var alertMessage = ""
    @State private var showAlert = false

    private let redFlags = [
        "Difficulty breathing",
        "Seizures or collapse",
        "Suspected poisoning",
        "Hit by a car or other major trauma",
        "Bloated or swollen belly with unproductive retching",
        "Unable to urinate, especially a male cat",
        "Pale or blue gums",
        "Uncontrolled bleeding",
        "Heatstroke warning signs",
        "Eye injury",
        "Prolonged labor or birthing trouble",
        "Snake or spider bite"
    ]

    var body: some View {
        List {
            Section {
                Text("If your pet has any of these warning signs, contact an emergency veterinarian immediately. This app cannot evaluate symptoms or urgency, and you should not wait for an email reply.")
                    .font(.headline)
                    .foregroundStyle(.red)
                    .listRowBackground(Color.red.opacity(0.1))
            }

            Section("Emergency warning signs") {
                Text("This list is not complete. If you are unsure or worried, contact a veterinarian now.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(redFlags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.primary)
                }
            }

            Section("Get help now") {
                Button {
                    openEmergencyVetLocator()
                } label: {
                    Label("Find an emergency vet near you", systemImage: "cross.case.fill")
                }

                Button {
                    callPoisonControl()
                } label: {
                    Label(
                        "Poison Control \(HelplineConfig.poisonControlDisplay)",
                        systemImage: "phone.fill"
                    )
                }

                Button {
                    copyPoisonControlNumber()
                } label: {
                    Label("Copy poison-control number", systemImage: "doc.on.doc")
                }

                Text("ASPCA Animal Poison Control is available 24/7 in the United States. A consultation fee may apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Provider & cost questions are free") {
                Text(HelplineConfig.freeProviderAndCostGuidance)
                    .font(.callout)
                if let url = HelplineConfig.californiaVeterinaryLicenseLookupURL {
                    Link("Verify a California veterinary license", destination: url)
                }
                Text("Do not delay urgent care while asking about cost. Tell the clinic you may have an emergency and ask what to do now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Emergency")
        .alert("Emergency Contact", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private func openEmergencyVetLocator() {
        guard let url = HelplineConfig.emergencyVetLocatorURL else {
            presentAlert("The emergency-vet locator address is unavailable.")
            return
        }

        openURL(url) { accepted in
            if !accepted {
                DispatchQueue.main.async {
                    presentAlert("The emergency-vet locator could not be opened. Search Maps for an emergency veterinarian near you.")
                }
            }
        }
    }

    private func callPoisonControl() {
        guard let url = HelplineConfig.poisonControlPhoneURL else {
            copyPoisonControlNumber()
            return
        }

        openURL(url) { accepted in
            if !accepted {
                DispatchQueue.main.async {
                    copyPoisonControlNumber(
                        message: "Calling is unavailable on this device. The poison-control number was copied."
                    )
                }
            }
        }
    }

    private func copyPoisonControlNumber(
        message: String = "The poison-control number was copied."
    ) {
        UIPasteboard.general.string = HelplineConfig.poisonControlNumber
        presentAlert(message)
    }

    private func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

#Preview {
    NavigationStack {
        EmergencyView()
    }
}
