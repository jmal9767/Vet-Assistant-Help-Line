import XCTest
@testable import VetAssistantHelpLine

final class QuestionDomainTests: XCTestCase {
    func testBundledCatalogIsUsableByBothSides() throws {
        let catalog = try ServiceCatalog.bundled()
        XCTAssertEqual(catalog.priceCents, 999)
        XCTAssertEqual(catalog.currency, "usd")
        XCTAssertEqual(catalog.clarificationDays, 7)
        XCTAssertEqual(catalog.categories.count, 5)
        XCTAssertEqual(Set(catalog.categories.map(\.id)).count, 5)
        let examples = catalog.categories.flatMap(\.examples)
        XCTAssertEqual(examples.count, 15)
        XCTAssertEqual(Set(examples).count, examples.count)
        XCTAssertFalse(catalog.answerChecklist.isEmpty)
        XCTAssertTrue(catalog.scope.contains("not a veterinarian"))
    }

    func testConnectionRejectsInsecureOrCredentialBearingURLs() throws {
        let token = String(repeating: "a", count: 64)
        for url in ["http://example.com", "https://user:password@example.com", "https://example.com?token=secret", "https://example.com#secret", "https://example.com/path"] {
            XCTAssertThrowsError(try InboxCredentials.validate(url: url, token: token), url)
        }
        XCTAssertThrowsError(try InboxCredentials.validate(url: "https://example.com", token: "sk_live_fake"))
        let value = try InboxCredentials.validate(url: "https://example.com/", token: token)
        XCTAssertEqual(value.baseURL.host, "example.com")
    }

    func testServerWireFormatAndReplyAreCompatible() throws {
        let question = try fixture()
        XCTAssertEqual(question.paymentIntent, "pi_test")
        XCTAssertEqual(question.mailState, "pending")
        XCTAssertTrue(question.needsAttention)
        XCTAssertFalse(question.canAnswer)
        let mail = try XCTUnwrap(question.mail)
        XCTAssertEqual(mail.recipient, "parent@example.com")
        XCTAssertTrue(mail.body.contains("Use headings for contacts"))
        XCTAssertTrue(mail.body.contains("Veterinary assistant"))
        XCTAssertFalse(mail.body.contains("pi_test"))
        XCTAssertFalse(mail.body.contains("token"))
    }

    func testHeldPaymentCannotBeAnsweredAndRemainsVisible() throws {
        let question = try fixture(state: "payment_hold", mailState: "queued")
        XCTAssertFalse(question.canAnswer)
        XCTAssertTrue(question.needsAttention)
    }

    func testUnresolvedEmailIsVisibleEvenForCompletedWork() throws {
        let question = try fixture(state: "closed", mailState: "unresolved")
        XCTAssertTrue(question.needsAttention)
        XCTAssertFalse(question.canAnswer)
    }

    @MainActor
    func testInboxStartsLockedAndLockClearsPrivateState() {
        let inbox = PrivateInbox()
        XCTAssertFalse(inbox.unlocked)
        XCTAssertTrue(inbox.questions.isEmpty)
        inbox.lock()
        XCTAssertFalse(inbox.unlocked)
        XCTAssertTrue(inbox.questions.isEmpty)
    }

    private func fixture(state: String = "answered", mailState: String = "pending") throws -> OperatorQuestion {
        let payload: [String: Any] = [
            "id": "fixture-question", "category": "organization", "question": "What belongs in a sitter handover?",
            "context": "A checklist for a household member.", "email": "parent@example.com", "format": "checklist",
            "state": state, "version": 2, "amount": 999, "currency": "usd", "created": 1788700000,
            "paid_at": 1788700000, "due": 1789000000, "answer_at": 1788800000,
            "clarification_deadline": 1789400000, "payment_intent": "pi_test", "mail_state": mailState, "note": "",
            "answer": ["summary": "Organize the information by what the sitter needs to find.", "practical": "Use headings for contacts, agreed tasks, supply locations, and check-in arrangements.", "boundary": "Clinical instructions come from the treating clinic.", "sources": ["https://www.avma.org/resources-tools/pet-owners/petcare"]]
        ]
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(OperatorQuestion.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
