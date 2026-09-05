import Foundation
import XCTest
@testable import VetAssistantHelpLine

final class QuestionCategorySchemaTests: XCTestCase {
    func testCategoriesAndGuidedQuestionsHaveCompleteStableIdentifiers() {
        let categories = QuestionCategory.allCases
        let expectedCategoryIDs: Set<String> = [
            "groomingConcepts",
            "enrichmentAndRoutines",
            "newPetEnvironment",
            "routineVisitPreparation"
        ]

        XCTAssertEqual(Set(categories.map(\.id)), expectedCategoryIDs)
        XCTAssertEqual(categories.count, expectedCategoryIDs.count)

        let questionIDs = categories.map(\.guidedQuestion.id)
        XCTAssertEqual(Set(questionIDs).count, questionIDs.count)

        for category in categories {
            let question = category.guidedQuestion

            XCTAssertFalse(category.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(category.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.supportingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(question.placeholder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

final class QuestionDraftValidationTests: XCTestCase {
    func testDraftRequiresCategoryAndNonblankAnswer() {
        var draft = QuestionDraft()

        XCTAssertFalse(draft.guidedAnswersAreComplete)
        XCTAssertFalse(draft.isReadyForReview)

        draft.selectCategory(.groomingConcepts)
        XCTAssertFalse(draft.guidedAnswersAreComplete)

        draft.setAnswer("  \n  ", for: QuestionCategory.groomingConcepts.guidedQuestion)
        XCTAssertFalse(draft.guidedAnswersAreComplete)

        draft.setAnswer(
            "  A general explanation of gradual brushing  ",
            for: QuestionCategory.groomingConcepts.guidedQuestion
        )

        XCTAssertTrue(draft.guidedAnswersAreComplete)
        XCTAssertTrue(draft.isReadyForReview)
    }

    func testAnswerIsTrimmedAndCapped() {
        var draft = QuestionDraft()
        let question = QuestionCategory.enrichmentAndRoutines.guidedQuestion
        draft.selectCategory(.enrichmentAndRoutines)

        let untrimmedAnswer = "  \n Rotate simple activities. \t "
        draft.setAnswer(untrimmedAnswer, for: question)
        XCTAssertEqual(draft.rawAnswer(for: question), untrimmedAnswer)
        XCTAssertEqual(draft.answer(for: question), "Rotate simple activities.")

        draft.setAnswer(
            String(repeating: "a", count: QuestionDraft.answerLimit + 25),
            for: question
        )
        XCTAssertEqual(draft.answer(for: question).count, QuestionDraft.answerLimit)
    }

    func testChangingCategoryClearsThePreviousAnswer() {
        var draft = QuestionDraft()
        let firstQuestion = QuestionCategory.groomingConcepts.guidedQuestion

        draft.selectCategory(.groomingConcepts)
        draft.setAnswer("Explain gradual brushing.", for: firstQuestion)
        XCTAssertTrue(draft.isReadyForReview)

        draft.selectCategory(.newPetEnvironment)

        XCTAssertEqual(draft.category?.id, QuestionCategory.newPetEnvironment.id)
        XCTAssertEqual(draft.answer(for: firstQuestion), "")
        XCTAssertEqual(
            draft.answer(for: QuestionCategory.newPetEnvironment.guidedQuestion),
            ""
        )
        XCTAssertFalse(draft.isReadyForReview)
    }

    func testClearCreatesAnEmptyDraftWithANewReference() {
        var draft = completeDraft(category: .routineVisitPreparation)
        let originalID = draft.id

        draft.clear()

        XCTAssertNotEqual(draft.id, originalID)
        XCTAssertNil(draft.category)
        XCTAssertFalse(draft.guidedAnswersAreComplete)
        XCTAssertFalse(draft.isReadyForReview)
    }
}

@MainActor
final class QuestionFlowModelTests: XCTestCase {
    func testEveryForwardGateIncludesAdultPurchaseConfirmation() {
        let model = QuestionFlowModel()

        model.continueFromSafety()
        assertStep(model, is: .safety)
        XCTAssertNotNil(model.validationMessage)

        model.confirmsNoEmergency = true
        model.confirmsEducationOnly = true
        model.confirmsVeterinaryCare = true
        model.continueFromSafety()
        assertStep(model, is: .category)

        model.continueFromCategory()
        assertStep(model, is: .category)
        XCTAssertNotNil(model.validationMessage)

        model.draft.selectCategory(.enrichmentAndRoutines)
        model.continueFromCategory()
        assertStep(model, is: .details)

        model.continueFromDetails()
        assertStep(model, is: .details)
        XCTAssertNotNil(model.validationMessage)

        model.draft.setAnswer(
            "Explain how activity rotation works in general.",
            for: QuestionCategory.enrichmentAndRoutines.guidedQuestion
        )
        model.continueFromDetails()
        assertStep(model, is: .review)

        model.acknowledgesResponseTime = true
        model.acknowledgesPurchase = true
        model.continueFromReview()
        assertStep(model, is: .review)
        XCTAssertFalse(model.reviewAcknowledgementsAreComplete)
        XCTAssertNotNil(model.validationMessage)

        model.confirmsAdultPurchase = true
        model.continueFromReview()
        assertStep(model, is: .purchase)
        XCTAssertTrue(model.reviewAcknowledgementsAreComplete)
        XCTAssertNil(model.validationMessage)
    }

    func testStartingAnotherQuestionClearsWorkflowDraftAndAcknowledgements() {
        let model = QuestionFlowModel()
        model.draft = completeDraft(category: .groomingConcepts)
        model.confirmsNoEmergency = true
        model.confirmsEducationOnly = true
        model.confirmsVeterinaryCare = true
        model.acknowledgesResponseTime = true
        model.acknowledgesPurchase = true
        model.confirmsAdultPurchase = true
        model.markSent()

        assertStep(model, is: .sent)
        model.startAnotherQuestion()

        assertStep(model, is: .safety)
        XCTAssertNil(model.draft.category)
        XCTAssertFalse(model.draft.isReadyForReview)
        XCTAssertFalse(model.confirmsNoEmergency)
        XCTAssertFalse(model.confirmsEducationOnly)
        XCTAssertFalse(model.confirmsVeterinaryCare)
        XCTAssertFalse(model.acknowledgesResponseTime)
        XCTAssertFalse(model.acknowledgesPurchase)
        XCTAssertFalse(model.confirmsAdultPurchase)
        XCTAssertNil(model.validationMessage)
    }

    func testBackingUpRequiresFreshReviewAcknowledgements() {
        let model = QuestionFlowModel()
        model.draft = completeDraft(category: .newPetEnvironment)
        model.confirmsNoEmergency = true
        model.confirmsEducationOnly = true
        model.confirmsVeterinaryCare = true
        model.continueFromSafety()
        model.continueFromCategory()
        model.continueFromDetails()
        model.acknowledgesResponseTime = true
        model.acknowledgesPurchase = true
        model.confirmsAdultPurchase = true

        model.goBack()

        assertStep(model, is: .details)
        XCTAssertFalse(model.reviewAcknowledgementsAreComplete)

        model.continueFromDetails()
        model.acknowledgesResponseTime = true
        model.acknowledgesPurchase = true
        model.confirmsAdultPurchase = true
        model.continueFromReview()
        assertStep(model, is: .purchase)

        model.goBack()

        assertStep(model, is: .review)
        XCTAssertFalse(model.reviewAcknowledgementsAreComplete)
    }

    private func assertStep(
        _ model: QuestionFlowModel,
        is expected: QuestionFlowStep,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(model.step.rawValue, expected.rawValue, file: file, line: line)
    }
}

final class QuestionEmailBuilderTests: XCTestCase {
    func testIncompleteDraftDoesNotCreateEmail() {
        XCTAssertNil(
            QuestionEmailBuilder.build(
                draft: QuestionDraft(),
                credit: testCredit()
            )
        )
    }

    func testCreditWithoutAppleQuestionBindingDoesNotCreateEmail() {
        XCTAssertNil(
            QuestionEmailBuilder.build(
                draft: completeDraft(category: .groomingConcepts),
                credit: testCredit(appAccountToken: nil)
            )
        )
    }

    func testCreditWithoutSignedAppleProofDoesNotCreateEmail() {
        let draft = completeDraft(category: .groomingConcepts)
        XCTAssertNil(
            QuestionEmailBuilder.build(
                draft: draft,
                credit: testCredit(
                    appAccountToken: draft.id,
                    signedTransactionJWS: ""
                )
            )
        )
    }

    func testCompleteDraftCreatesTraceableEncodedEmail() throws {
        let draftID = try XCTUnwrap(
            UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")
        )
        var draft = QuestionDraft(id: draftID)
        let category = QuestionCategory.routineVisitPreparation
        let answer = "How can I organize appointment logistics and nonmedical questions?"
        draft.selectCategory(category)
        draft.setAnswer("  \(answer)  ", for: category.guidedQuestion)

        let credit = testCredit(
            id: 9_876_543_210,
            appAccountToken: draftID,
            environment: "Production",
            signedTransactionJWS: "header.payload.signature"
        )
        let email = try XCTUnwrap(
            QuestionEmailBuilder.build(
                draft: draft,
                credit: credit
            )
        )

        XCTAssertEqual(email.recipient, HelplineConfig.recipientEmail)
        XCTAssertTrue(email.subject.hasPrefix(HelplineConfig.emailSubjectPrefix))
        XCTAssertTrue(email.subject.contains(category.title))
        XCTAssertTrue(email.subject.contains("[01234567]"))
        XCTAssertTrue(email.body.contains("Submission reference / Apple app-account token: \(draftID.uuidString)"))
        XCTAssertTrue(email.body.contains("Apple transaction reference: 9876543210"))
        XCTAssertTrue(email.body.contains("Apple environment: Production"))
        XCTAssertEqual(
            email.body.components(separatedBy: draftID.uuidString).count - 1,
            1
        )
        XCTAssertTrue(email.body.contains("header.payload.signature"))
        XCTAssertTrue(email.body.contains(category.title))
        XCTAssertTrue(email.body.contains(category.guidedQuestion.prompt))
        XCTAssertTrue(email.body.contains(answer))
        XCTAssertTrue(email.body.contains(HelplineConfig.emailAttestationSummary))

        let url = try XCTUnwrap(email.fallbackMailtoURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "mailto")
        XCTAssertEqual(components.path, HelplineConfig.recipientEmail)

        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            }
        )
        XCTAssertEqual(query["subject"], email.subject)
        XCTAssertNil(query["body"])
        XCTAssertTrue(email.clipboardText.contains("To: \(HelplineConfig.recipientEmail)"))
        XCTAssertTrue(email.clipboardText.contains("Subject: \(email.subject)"))
    }
}

@MainActor
final class PurchaseStoreJournalTests: XCTestCase {
    func testInitializationPreservesHandoffTombstonesAcrossAccountChanges() {
        let suiteName = "PurchaseStoreJournalTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            ["100", "200"],
            forKey: PurchaseStore.deliveryJournalKey
        )
        defaults.set(
            ["200", "300"],
            forKey: PurchaseStore.handoffJournalKey
        )
        _ = PurchaseStore(
            userDefaults: defaults,
            startAutomatically: false
        )

        XCTAssertEqual(
            defaults.stringArray(forKey: PurchaseStore.deliveryJournalKey),
            ["100", "200"]
        )
        XCTAssertEqual(
            defaults.stringArray(forKey: PurchaseStore.handoffJournalKey),
            ["200", "300"]
        )
    }

    func testCompletedTransactionReferenceExpiresAfterNinetyDays() {
        let suiteName = "PurchaseStoreCompletedReferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "123456789",
            forKey: PurchaseStore.lastCompletedTransactionIDKey
        )
        defaults.set(
            Date().addingTimeInterval(-91 * 24 * 60 * 60).timeIntervalSince1970,
            forKey: PurchaseStore.lastCompletedTransactionDateKey
        )

        let expiredStore = PurchaseStore(
            userDefaults: defaults,
            startAutomatically: false
        )
        XCTAssertNil(expiredStore.lastCompletedTransactionReference)
        XCTAssertNil(
            defaults.string(forKey: PurchaseStore.lastCompletedTransactionIDKey)
        )

        defaults.set(
            "987654321",
            forKey: PurchaseStore.lastCompletedTransactionIDKey
        )
        defaults.set(
            Date().timeIntervalSince1970,
            forKey: PurchaseStore.lastCompletedTransactionDateKey
        )
        let currentStore = PurchaseStore(
            userDefaults: defaults,
            startAutomatically: false
        )
        XCTAssertEqual(
            currentStore.lastCompletedTransactionReference,
            "987654321"
        )
    }

    func testCompletedTransactionReferenceRejectsMalformedStoredValue() {
        let suiteName = "PurchaseStoreMalformedReferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(
            "not-a-transaction",
            forKey: PurchaseStore.lastCompletedTransactionIDKey
        )
        defaults.set(
            Date().timeIntervalSince1970,
            forKey: PurchaseStore.lastCompletedTransactionDateKey
        )

        let store = PurchaseStore(
            userDefaults: defaults,
            startAutomatically: false
        )

        XCTAssertNil(store.lastCompletedTransactionReference)
        XCTAssertNil(
            defaults.string(forKey: PurchaseStore.lastCompletedTransactionIDKey)
        )

        defaults.set(
            "123456789",
            forKey: PurchaseStore.lastCompletedTransactionIDKey
        )
        defaults.set(
            Date().addingTimeInterval(24 * 60 * 60).timeIntervalSince1970,
            forKey: PurchaseStore.lastCompletedTransactionDateKey
        )

        let futureDatedStore = PurchaseStore(
            userDefaults: defaults,
            startAutomatically: false
        )
        XCTAssertNil(futureDatedStore.lastCompletedTransactionReference)
        XCTAssertNil(
            defaults.string(forKey: PurchaseStore.lastCompletedTransactionIDKey)
        )
    }
}

private func completeDraft(category: QuestionCategory) -> QuestionDraft {
    var draft = QuestionDraft()
    draft.selectCategory(category)
    draft.setAnswer(
        "A complete, eligible general-education question.",
        for: category.guidedQuestion
    )
    return draft
}

private func testCredit(
    id: UInt64 = 42,
    appAccountToken: UUID? = nil,
    environment: String = "Xcode",
    signedTransactionJWS: String = "test.header.payload.signature"
) -> PaidQuestionCredit {
    PaidQuestionCredit(
        id: id,
        productID: HelplineConfig.educationQuestionProductID,
        purchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
        appAccountToken: appAccountToken,
        environment: environment,
        signedTransactionJWS: signedTransactionJWS
    )
}
