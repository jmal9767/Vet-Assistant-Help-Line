import CloudKit
import Foundation
import Observation

@Observable
@MainActor
final class QuestionStore {
    private(set) var questions: [ClientQuestion] = []
    private(set) var archivedQuestions: [ClientQuestion] = []
    private(set) var isLoading = false
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
        isLoading = true
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
            let decoded = records.map(ClientQuestion.init)
            questions = decoded.filter { $0.status != .archived }
            archivedQuestions = decoded.filter { $0.status == .archived }
            errorMessage = firstRecordError.map { "Some questions couldn’t be loaded: \($0.localizedDescription). Pull to refresh to try again." }
        } catch {
            errorMessage = "Couldn't load questions: \(error.localizedDescription)"
        }
    }

    func setStatus(_ status: ClientQuestion.Status, for question: ClientQuestion) async {
        question.record["status"] = status.rawValue
        if status == .answered { question.setString("Closed", for: "conversationStatus") }
        if status == .new { question.setString("Needs response", for: "conversationStatus") }
        await save(question.record, failureMessage: "Couldn't update the question")
    }

    func updatePayment(status: String, amount: String? = nil, link: String? = nil, for question: ClientQuestion) async {
        question.setString(status, for: "paymentStatus")
        if let amount { question.setString(amount, for: "paymentAmount") }
        if let link { question.setString(link, for: "paymentLink") }
        await save(question.record, failureMessage: "Couldn't update the payment")
    }

    func requestPayment(amount: String, link: String, for question: ClientQuestion) async {
        question.setString("Payment requested", for: "paymentStatus")
        question.setString(amount, for: "paymentAmount")
        question.setString(link, for: "paymentLink")
        await save(question.record, failureMessage: "Couldn't save the payment request")
    }

    func deletePermanently(_ question: ClientQuestion) async {
        do {
            try await database.deleteRecord(withID: question.id)
            questions.removeAll { $0.id == question.id }
            archivedQuestions.removeAll { $0.id == question.id }
        } catch {
            errorMessage = "Couldn't delete the question: \(error.localizedDescription)"
        }
    }

    private func save(_ record: CKRecord, failureMessage: String) async {
        do {
            _ = try await database.save(record)
            await refresh()
        } catch {
            let message = "\(failureMessage): \(error.localizedDescription)"
            await refresh()
            errorMessage = message
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
