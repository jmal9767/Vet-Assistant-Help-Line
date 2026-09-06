import Foundation

struct EducationAnswer: Codable, Equatable {
    var summary: String
    var practical: String
    var boundary: String
    var sources: [String]
    var text: String {
        "\(summary)\n\n\(practical)\n\n\(boundary)\n\nSources\n" + sources.joined(separator: "\n")
    }
}

struct OperatorQuestion: Decodable, Identifiable {
    let id: String
    let category: String
    let question: String
    let context: String
    let email: String
    let format: String
    let state: String
    let version: Int
    let amount: Int
    let currency: String
    let created: Int
    let paidAt: Int?
    let due: Int?
    let answer: EducationAnswer?
    let answerAt: Int?
    let clarification: String?
    let clarificationAnswer: EducationAnswer?
    let clarificationDue: Int?
    let clarificationDeadline: Int?
    let paymentIntent: String?
    let mailState: String
    let note: String

    var latestAnswer: EducationAnswer? { clarificationAnswer ?? answer }
    var canAnswer: Bool { state == "paid" || state == "clarification" }
    var needsAttention: Bool {
        canAnswer || state == "refund_requested" || state == "payment_hold" || mailState == "pending" || mailState == "unresolved"
    }
    var target: Date? { (clarificationDue ?? due).map { Date(timeIntervalSince1970: Double($0)) } }
    var overdue: Bool { canAnswer && (target.map { $0 < Date() } ?? false) }
    var statusTitle: String {
        switch state {
        case "paid": "Awaiting your review"
        case "answered": "Answered"
        case "clarification": "Clarification needed"
        case "closed": "Complete"
        case "refund_requested": "Refund needs attention"
        case "refunded": "Refunded"
        case "payment_hold": "Reconcile payment"
        default: "Review status"
        }
    }
    var mail: QuestionEmail? {
        guard let latestAnswer else { return nil }
        let clarificationText = clarificationDeadline.map {
            "Your included same-topic clarification can be requested on your saved private question page by \(Self.pacificDate($0))."
        } ?? ""
        return QuestionEmail(recipient: email,
            subject: "Your pet-care education answer [\(id)]",
            body: "Hello,\n\nYou asked: \(question)\n\n\(latestAnswer.text)\n\n\(clarificationAnswer == nil ? clarificationText : "This completes your included clarification.")\n\nJahmal Parris\nVeterinary assistant · Bay Area Apps LLC\nGeneral nonmedical education, not veterinary care. Not monitored for emergencies.\nReference: \(id)")
    }
    static func pacificDate(_ timestamp: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium; formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "America/Los_Angeles")
        return formatter.string(from: Date(timeIntervalSince1970: Double(timestamp))) + " Pacific Time"
    }
}

struct QuestionEmail { let recipient: String; let subject: String; let body: String }
struct InboxResponse: Decodable { let questions: [OperatorQuestion]; let accepting: Bool; let live: Bool }
enum InboxError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
