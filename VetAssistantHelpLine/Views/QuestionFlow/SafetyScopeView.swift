import SwiftUI

struct SafetyScopeView: View {
    @ObservedObject var model: QuestionFlowModel
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                Label("This check is always free", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text("Complete it before choosing a question category or making a purchase.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Do not continue for medical concerns") {
                Text(HelplineConfig.scopeStatement)
                    .font(.callout)

                Text("Warning-sign examples are never a complete screening list. If you are unsure or worried about a pet, contact a licensed veterinarian now instead of using this service.")
                    .font(.callout.weight(.semibold))

                Text("In the United States, possible poisoning can also be directed to ASPCA Animal Poison Control at \(HelplineConfig.poisonControlDisplay); a consultation fee may apply.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    EmergencyView()
                } label: {
                    Label(
                        "Emergency signs and immediate contacts",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section("Confirm all three") {
                Toggle(
                    HelplineConfig.noEmergencyAcknowledgement,
                    isOn: $model.confirmsNoEmergency
                )
                Toggle(
                    HelplineConfig.educationOnlyAcknowledgement,
                    isOn: $model.confirmsEducationOnly
                )
                Toggle(
                    HelplineConfig.veterinaryCareAcknowledgement,
                    isOn: $model.confirmsVeterinaryCare
                )
            }

            Section {
                FlowValidationMessage(message: model.validationMessage)
                Button("Continue to question topics", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHint("Available after all three safety statements are confirmed.")
            }
        }
    }
}
