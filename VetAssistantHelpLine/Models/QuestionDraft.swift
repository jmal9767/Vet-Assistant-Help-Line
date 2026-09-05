import Foundation

struct QuestionDraft: Sendable {
    static let answerLimit = 800

    let id: UUID
    var category: QuestionCategory?
    private(set) var answers: [String: String] = [:]

    init(id: UUID = UUID()) {
        self.id = id
    }

    var guidedAnswersAreComplete: Bool {
        guard let category else { return false }
        return !answer(for: category.guidedQuestion).isEmpty
    }

    var isReadyForReview: Bool {
        category != nil && guidedAnswersAreComplete
    }

    mutating func selectCategory(_ newCategory: QuestionCategory) {
        guard category != newCategory else { return }
        category = newCategory
        answers.removeAll()
    }

    func answer(for question: GuidedQuestion) -> String {
        rawAnswer(for: question)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rawAnswer(for question: GuidedQuestion) -> String {
        answers[question.id, default: ""]
    }

    mutating func setAnswer(_ answer: String, for question: GuidedQuestion) {
        answers[question.id] = String(answer.prefix(Self.answerLimit))
    }

    mutating func clear() {
        self = QuestionDraft()
    }
}

enum QuestionFlowStep: Int, Sendable {
    case safety
    case category
    case details
    case review
    case purchase
    case sent

    var title: String {
        switch self {
        case .safety: "Safety First"
        case .category: "Choose a Topic"
        case .details: "Your Question"
        case .review: "Review"
        case .purchase: "Purchase & Send"
        case .sent: "Email Handoff Complete"
        }
    }

    var allowsBackNavigation: Bool {
        self != .safety && self != .sent
    }
}
