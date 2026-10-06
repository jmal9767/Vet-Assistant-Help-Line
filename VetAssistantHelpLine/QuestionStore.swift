import CloudKit
import Foundation
import Observation

@Observable
@MainActor
final class QuestionStore {
    private(set) var questions: [ClientQuestion] = []
    private(set) var archivedQuestions: [ClientQuestion] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    @ObservationIgnored private var recordRevision = 0
    var errorMessage: String?
    private(set) var notificationSetupError: String?
    private(set) var notificationSetupComplete = false

    private let database = CKContainer.default().publicCloudDatabase
    private static let subscriptionID = "new-question-alerts"

    var newQuestions: [ClientQuestion] { questions.filter { $0.status == .new } }
    var answeredQuestions: [ClientQuestion] { questions.filter { $0.status == .answered } }

    func question(recordName: String) -> ClientQuestion? {
        (questions + archivedQuestions).first { $0.id.recordName == recordName }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        let revision = recordRevision
        defer { isLoading = false }
        do {
            let query = CKQuery(recordType: ClientQuestion.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "submittedAt", ascending: false)]
            var records: [CKRecord] = []
            var firstRecordError: Error?
            var (matches, cursor) = try await database.records(matching: query, resultsLimit: 100)
            while true {
                for (_, result) in matches {
                    switch result {
                    case let .success(record): records.append(record)
                    case let .failure(error):
                        if firstRecordError == nil { firstRecordError = error }
                    }
                }
                guard let next = cursor else { break }
                (matches, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: 100)
            }
            guard revision == recordRevision else { return }
            let decoded = records.map(ClientQuestion.init)
            questions = decoded.filter { $0.status != .archived }
            archivedQuestions = decoded.filter { $0.status == .archived }
            errorMessage = firstRecordError.map { "Some questions couldn’t be loaded: \($0.localizedDescription). Pull to refresh to try again." }
        } catch {
            errorMessage = "Couldn't load questions: \(error.localizedDescription)"
        }
    }

    func setStatus(_ status: ClientQuestion.Status, for question: ClientQuestion) async {
        await update(question, failureMessage: "Couldn't update the question") { current in
            current.record["status"] = status.rawValue
            if status == .answered { current.setString("Closed", for: "conversationStatus") }
            if status == .new {
                if current.paymentStatus == "Declined — no charge" { current.setString("Awaiting approval", for: "paymentStatus") }
                current.setString(current.awaitingApproval ? "Awaiting approval" : "Needs response", for: "conversationStatus")
            }
        }
    }

    func decideAvailability(approved: Bool, for question: ClientQuestion) async {
        await update(question, failureMessage: "Couldn't save your availability decision") { current in
            try current.recordAvailabilityDecision(approved: approved)
        }
    }

    private func update(_ question: ClientQuestion, failureMessage: String, change: (ClientQuestion) throws -> Void) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            // Fetch a fresh record and reject conflicting edits from another device.
            let record = try await database.record(for: question.id)
            try change(ClientQuestion(record: record))
            let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: false)
            guard let savedResult = result.saveResults[record.recordID] else { throw CKError(.internalError) }
            let saved = ClientQuestion(record: try savedResult.get())
            recordRevision += 1
            questions.removeAll { $0.id == saved.id }
            archivedQuestions.removeAll { $0.id == saved.id }
            if saved.status == .archived { archivedQuestions.append(saved) } else { questions.append(saved) }
            questions.sort { $0.submittedAt > $1.submittedAt }
            archivedQuestions.sort { $0.submittedAt > $1.submittedAt }
            await refresh()
        } catch {
            await refresh()
            errorMessage = "\(failureMessage): \(error.localizedDescription)"
        }
    }

    func deletePermanently(_ question: ClientQuestion) async {
        do {
            if let token = question.conversationToken { try await CareLineConversationService().remove(token) }
            try await database.deleteRecord(withID: question.id)
            questions.removeAll { $0.id == question.id }
            archivedQuestions.removeAll { $0.id == question.id }
        } catch {
            errorMessage = "Couldn't delete the question: \(error.localizedDescription)"
        }
    }

    func ensureSubscription() async {
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            notificationSetupComplete = true
            notificationSetupError = nil
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Create it below.
        } catch {
            notificationSetupComplete = false
            notificationSetupError = "Couldn’t set up Inbox alerts: \(error.localizedDescription)"
            return
        }

        let subscription = CKQuerySubscription(
            recordType: ClientQuestion.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: Self.subscriptionID,
            options: .firesOnRecordCreation
        )
        let info = CKSubscription.NotificationInfo()
        info.title = "New Paws & Whiskers question"
        info.alertBody = "A client sent a new question."
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info
        do {
            _ = try await database.save(subscription)
            notificationSetupComplete = true
            notificationSetupError = nil
        } catch {
            notificationSetupComplete = false
            notificationSetupError = "Couldn’t set up Inbox alerts: \(error.localizedDescription)"
        }
    }
}
