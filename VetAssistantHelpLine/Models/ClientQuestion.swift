import CloudKit
import Foundation

struct ClientQuestion: Identifiable {
    static let recordType = "Question"

    enum Status: String {
        case new
        case answered
        case archived
    }

    struct Attachment: Identifiable {
        let id = UUID()
        let name: String
        let detail: String
        let url: URL?
    }

    let record: CKRecord

    var id: CKRecord.ID { record.recordID }
    var name: String { string(for: "name") ?? "Anonymous" }
    var email: String { string(for: "email") ?? "" }
    var phone: String? { string(for: "phone") }
    var preferredReply: String { string(for: "preferredReply") ?? (phone == nil ? "Email" : "Text message") }
    var requestedService: String { string(for: "requestedService") ?? preferredReply }
    var petName: String { string(for: "petName") ?? "Pet" }
    var species: String { string(for: "species") ?? "Unknown" }
    var age: String { string(for: "age") ?? "Not given" }
    var category: String { string(for: "category") ?? "Other" }
    var urgency: String { string(for: "urgency") ?? "Not specified" }
    var question: String { string(for: "question") ?? "" }
    var attachmentSummary: String? { string(for: "attachmentSummary") }
    var sourceChannel: String { string(for: "sourceChannel") ?? "Website" }
    var conversationStatus: String { string(for: "conversationStatus") ?? "Needs response" }
    var paymentStatus: String { string(for: "paymentStatus") ?? "Reviewing" }
    var paymentMethod: String { string(for: "paymentMethod") ?? "Client has no preference" }
    var paymentAmount: String { string(for: "paymentAmount") ?? amountFromRequestedService }
    var paymentLink: String? { string(for: "paymentLink") }
    var signedConsentName: String? { string(for: "signedConsentName") }
    var signedConsentAt: String? { string(for: "signedConsentAt") }

    var submittedAt: Date { record["submittedAt"] as? Date ?? record.creationDate ?? .distantPast }
    var status: Status { Status(rawValue: string(for: "status") ?? "") ?? .new }
    var attachments: [Attachment] {
        guard let attachmentSummary else { return [] }
        return attachmentSummary.split(separator: "\n").map { line in
            let value = String(line)
            if let separator = value.range(of: " - https://") {
                let detail = String(value[..<separator.lowerBound])
                let urlText = "https://" + value[separator.upperBound...]
                let name = detail.components(separatedBy: " (").first ?? "Attachment"
                return Attachment(name: name, detail: detail, url: URL(string: String(urlText)))
            }
            return Attachment(name: value.components(separatedBy: " (").first ?? "Attachment", detail: value, url: nil)
        }
    }

    private func string(for key: String) -> String? {
        guard let value = record[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private var amountFromRequestedService: String {
        guard let range = requestedService.range(of: "$", options: .backwards) else { return "Confirm" }
        return String(requestedService[range.lowerBound...])
    }
}
