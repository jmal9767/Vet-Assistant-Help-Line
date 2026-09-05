import SwiftUI

struct QuestionDetailsView: View {
    @ObservedObject var model: QuestionFlowModel
    let onContinue: () -> Void

    var body: some View {
        Form {
            if let category = model.draft.category {
                Section("Selected topic") {
                    Text(category.title)
                        .font(.headline)
                    Text(category.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField(
                        category.guidedQuestion.placeholder,
                        text: answerBinding(for: category.guidedQuestion),
                        axis: .vertical
                    )
                    .lineLimit(4...10)
                    .accessibilityLabel(category.guidedQuestion.prompt)
                } header: {
                    Text(category.guidedQuestion.prompt)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.guidedQuestion.supportingText)
                        Text("\(model.draft.rawAnswer(for: category.guidedQuestion).count) of \(QuestionDraft.answerLimit) characters")
                    }
                }
            }

            Section {
                Text(HelplineConfig.questionDataWarning)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                FlowValidationMessage(message: model.validationMessage)
                Button("Review question", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private func answerBinding(for question: GuidedQuestion) -> Binding<String> {
        Binding(
            get: { model.draft.rawAnswer(for: question) },
            set: { model.draft.setAnswer($0, for: question) }
        )
    }
}
