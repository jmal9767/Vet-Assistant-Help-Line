import SwiftUI

struct QuestionReviewView: View {
    @ObservedObject var model: QuestionFlowModel
    let onContinue: () -> Void

    var body: some View {
        List {
            if let category = model.draft.category {
                Section("Topic") {
                    Text(category.title)
                        .font(.headline)
                }

                Section("Your one general question") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.guidedQuestion.prompt)
                            .font(.subheadline.weight(.semibold))
                        Text(model.draft.answer(for: category.guidedQuestion))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Toggle(
                    HelplineConfig.responseTimeAcknowledgement,
                    isOn: $model.acknowledgesResponseTime
                )
                Toggle(
                    HelplineConfig.purchaseAcknowledgement,
                    isOn: $model.acknowledgesPurchase
                )
                Toggle(
                    HelplineConfig.adultPurchaseAcknowledgement,
                    isOn: $model.confirmsAdultPurchase
                )
            } header: {
                Text("Before purchasing")
            } footer: {
                Text("Review your question now. You can go back to make changes before Apple's purchase screen appears.")
            }

            Section("Policies") {
                NavigationLink("Privacy") {
                    PrivacyView()
                }
                NavigationLink("Terms") {
                    TermsView()
                }
            }

            Section {
                FlowValidationMessage(message: model.validationMessage)
                Button("Continue to purchase", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityHint("Available after all three acknowledgements are confirmed.")
            }
        }
    }
}
