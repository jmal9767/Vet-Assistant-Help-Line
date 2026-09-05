import SwiftUI

struct CategorySelectionView: View {
    @ObservedObject var model: QuestionFlowModel
    let onContinue: () -> Void

    var body: some View {
        List {
            Section {
                Text("Choose the one neutral, nonmedical topic that best matches your general question.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Question topics") {
                ForEach(QuestionCategory.allCases) { category in
                    Button {
                        model.draft.selectCategory(category)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(category.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(category.summary)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(
                                systemName: model.draft.category == category
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .foregroundStyle(
                                model.draft.category == category
                                    ? Color.accentColor
                                    : Color.secondary
                            )
                            .accessibilityHidden(true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "\(category.title). \(category.summary)"
                    )
                    .accessibilityValue(
                        model.draft.category == category ? "Selected" : "Not selected"
                    )
                }
            }

            Section {
                FlowValidationMessage(message: model.validationMessage)
                Button("Continue", action: onContinue)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
