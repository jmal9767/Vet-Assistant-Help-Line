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
            var (matches, cursor) = try await database.records(matching: query, resultsLimit: 100)
            while true {
                for result in matches.values {
                    if case let .success(record) = result { records.append(record) }
                }
                guard let next = cursor else { break }
                (matches, cursor) = try await database.records(continuingMatchFrom: next, resultsLimit: 100)
            }
            let decoded = records.map(ClientQuestion.init)
            questions = decoded.filter { $0.status != .archived }
            archivedQuestions = decoded.filter { $0.status == .archived }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load questions: \(error.localizedDescription)"
        }
    }

    func setStatus(_ status: ClientQuestion.Status, for question: ClientQuestion) async {
        question.record["status"] = status.rawValue
        if status == .answered { question.record["conversationStatus"] = "Closed" }
        if status == .new { question.record["conversationStatus"] = "Needs response" }
        await save(question.record, failureMessage: "Couldn't update the question")
    }

    func updatePayment(status: String, amount: String? = nil, link: String? = nil, for question: ClientQuestion) async {
        question.record["paymentStatus"] = status
        if let amount { question.record["paymentAmount"] = amount }
        if let link { question.record["paymentLink"] = link }
        await save(question.record, failureMessage: "Couldn't update the payment")
    }

    func makeComplimentary(replyMethod: String, for question: ClientQuestion) async {
        question.record["paymentStatus"] = "Complimentary"
        question.record["paymentAmount"] = "$0"
        question.record["paymentMethod"] = "No charge"
        question.record["paymentLink"] = ""
        question.record["preferredReply"] = replyMethod
        question.record["requestedService"] = "Complimentary \(replyMethod.lowercased())"
        await save(question.record, failureMessage: "Couldn't make this service complimentary")
    }

    func requestPayment(amount: String, link: String, for question: ClientQuestion) async {
        question.record["paymentStatus"] = "Payment requested"
        question.record["paymentAmount"] = amount
        question.record["paymentLink"] = link
        await save(question.record, failureMessage: "Couldn't save the payment request")
    }

    func applyServiceOffer(
        name: String,
        replyMethod: String,
        amount: String,
        paymentMethod: String,
        paymentLink: String,
        paymentStatus: String,
        for question: ClientQuestion
    ) async {
        question.record["requestedService"] = name
        question.record["preferredReply"] = replyMethod
        question.record["paymentAmount"] = amount
        question.record["paymentLink"] = paymentLink
        question.record["paymentStatus"] = paymentStatus
        question.record["paymentMethod"] = paymentStatus == "Payment requested" ? paymentMethod : "No charge"
        if paymentStatus == "Referred — no charge" {
            question.record["status"] = ClientQuestion.Status.answered.rawValue
            question.record["conversationStatus"] = "Closed"
        }
        await save(question.record, failureMessage: "Couldn't save the service decision")
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
            errorMessage = "\(failureMessage): \(error.localizedDescription)"
            await refresh()
        }
    }

    func ensureSubscription() async {
        do {
            _ = try await database.subscription(for: Self.subscriptionID)
            return
        } catch let error as CKError where error.code == .unknownItem {
            // Create it below.
        } catch {
            return
        }

        let subscription = CKQuerySubscription(
            recordType: ClientQuestion.recordType,
            predicate: NSPredicate(value: true),
            subscriptionID: Self.subscriptionID,
            options: .firesOnRecordCreation
        )
        let info = CKSubscription.NotificationInfo()
        info.title = "New help-line question"
        info.alertBody = "A client sent a new question."
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info
        do { _ = try await database.save(subscription) } catch { }
    }
}
