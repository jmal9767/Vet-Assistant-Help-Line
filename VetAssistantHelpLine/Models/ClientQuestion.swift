import CloudKit
import Foundation

/// A question submitted by a pet owner through the help-line website,
/// stored as a "Question" record in the CloudKit public database.
struct ClientQuestion: Identifiable {
    static let recordType = "Question"

    enum Status: String {
        case new
        case answered
        case archived
    }

    let record: CKRecord

    var id: CKRecord.ID { record.recordID }

    var name: String { string(for: "name") ?? "Anonymous" }
    var email: String { string(for: "email") ?? "" }
    /// Set only when the client asked for a text-message reply.
    var phone: String? { string(for: "phone") }
    var species: String { string(for: "species") ?? "Unknown" }
    var age: String { string(for: "age") ?? "Not given" }
    var category: String { string(for: "category") ?? "Other" }
    var question: String { string(for: "question") ?? "" }

    var submittedAt: Date {
        record["submittedAt"] as? Date ?? record.creationDate ?? .distantPast
    }

    var status: Status {
        Status(rawValue: string(for: "status") ?? "") ?? .new
    }

    private func string(for key: String) -> String? {
        guard let value = record[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}
