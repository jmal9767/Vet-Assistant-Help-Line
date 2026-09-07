import CloudKit
import Foundation
import Observation

/// Loads client questions from the CloudKit public database and keeps
/// their status (new / answered / archived) in sync.
@Observable
@MainActor
final class QuestionStore {
    private(set) var questions: [ClientQuestion] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let database = CKContainer.default().publicCloudDatabase
    private static let subscriptionID = "new-question-alerts"

    var newQuestions: [ClientQuestion] { questions.filter { $0.status == .new } }
    var answeredQuestions: [ClientQuestion] { questions.filter { $0.status == .answered } }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let query = CKQuery(recordType: ClientQuestion.recordType,
                                predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "submittedAt", ascending: false)]

            var records: [CKRecord] = []
            var (matchResults, cursor) = try await database.records(matching: query)
            while true {
                records.append(contentsOf: matchResults.compactMap { try? $0.1.get() })
                guard let next = cursor else { break }
                (matchResults, cursor) = try await database.records(continuingMatchFrom: next)
            }

            questions = records.map(ClientQuestion.init)
                .filter { $0.status != .archived }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load questions: \(error.localizedDescription)"
        }
    }

    func setStatus(_ status: ClientQuestion.Status, for question: ClientQuestion) async {
        let record = question.record
        record["status"] = status.rawValue
        do {
            let saved = try await database.save(record)
            if status == .archived {
                questions.removeAll { $0.id == saved.recordID }
            } else if let index = questions.firstIndex(where: { $0.id == saved.recordID }) {
                questions[index] = ClientQuestion(record: saved)
            }
        } catch {
            errorMessage = "Couldn't update the question: \(error.localizedDescription)"
        }
    }

    /// Registers a push notification for newly created questions.
    /// Safe to call on every launch; an already-registered subscription is left alone.
    func ensureSubscription() async {
        let subscription = CKQuerySubscription(recordType: ClientQuestion.recordType,
                                               predicate: NSPredicate(value: true),
                                               subscriptionID: Self.subscriptionID,
                                               options: .firesOnRecordCreation)
        let info = CKSubscription.NotificationInfo()
        info.title = "New help-line question"
        info.alertBody = "A client just sent a question."
        info.soundName = "default"
        info.shouldBadge = true
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // The subscription already exists — nothing to do.
        } catch {
            // Push registration is best-effort; pull-to-refresh still works without it.
        }
    }
}
