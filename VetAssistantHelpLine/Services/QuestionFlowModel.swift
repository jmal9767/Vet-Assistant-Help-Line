import Combine
import Foundation

@MainActor
final class QuestionFlowModel: ObservableObject {
    @Published private(set) var step: QuestionFlowStep = .safety
    @Published var draft = QuestionDraft()

    @Published var confirmsNoEmergency = false
    @Published var confirmsEducationOnly = false
    @Published var confirmsVeterinaryCare = false

    @Published var acknowledgesResponseTime = false
    @Published var acknowledgesPurchase = false
    @Published var confirmsAdultPurchase = false

    @Published private(set) var validationMessage: String?

    var safetyScreenIsComplete: Bool {
        confirmsNoEmergency
            && confirmsEducationOnly
            && confirmsVeterinaryCare
    }

    var reviewAcknowledgementsAreComplete: Bool {
        acknowledgesResponseTime
            && acknowledgesPurchase
            && confirmsAdultPurchase
    }

    func continueFromSafety() {
        guard safetyScreenIsComplete else {
            validationMessage = "Confirm all three safety statements before choosing a topic."
            return
        }

        validationMessage = nil
        step = .category
    }

    func continueFromCategory() {
        guard draft.category != nil else {
            validationMessage = "Choose one general pet-care topic to continue."
            return
        }

        validationMessage = nil
        step = .details
    }

    func continueFromDetails() {
        guard draft.guidedAnswersAreComplete else {
            validationMessage = "Enter one general question before continuing."
            return
        }

        validationMessage = nil
        step = .review
    }

    func continueFromReview() {
        guard reviewAcknowledgementsAreComplete else {
            validationMessage = "Confirm all three statements before continuing to Apple's purchase screen."
            return
        }

        validationMessage = nil
        step = .purchase
    }

    func goBack() {
        validationMessage = nil

        switch step {
        case .category:
            step = .safety
        case .details:
            step = .category
        case .review:
            resetReviewAcknowledgements()
            step = .details
        case .purchase:
            resetReviewAcknowledgements()
            step = .review
        case .safety, .sent:
            break
        }
    }

    func markSent() {
        validationMessage = nil
        step = .sent
    }

    func startAnotherQuestion() {
        draft.clear()
        confirmsNoEmergency = false
        confirmsEducationOnly = false
        confirmsVeterinaryCare = false
        resetReviewAcknowledgements()
        validationMessage = nil
        step = .safety
    }

    private func resetReviewAcknowledgements() {
        acknowledgesResponseTime = false
        acknowledgesPurchase = false
        confirmsAdultPurchase = false
    }
}
