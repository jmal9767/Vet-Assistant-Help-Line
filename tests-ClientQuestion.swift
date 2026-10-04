import Foundation
import CloudKit

@main
struct VerifyClientQuestion {
    static func main() throws {
        let record = CKRecord(recordType: "Question", recordID: CKRecord.ID(recordName: "fictional-test"))
        record["name"] = "Fictional operator test"
        let body: [String: Any] = ["format": "paws-intake-v1", "question": "An enrichment question", "details": ["breed": "Fictional mix", "paymentAmount": "$0", "paymentStatus": "No payment required", "signedConsentName": "Fictional test", "conversationStatus": "Needs response"]]
        record["question"] = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        let question = ClientQuestion(record: record)
        precondition(question.question == "An enrichment question")
        precondition(question.breed == "Fictional mix")
        precondition(question.paymentAmount == "$0")
        precondition(question.signedConsentName == "Fictional test")
        question.setString("Closed", for: "conversationStatus")
        precondition(question.conversationStatus == "Closed")
        precondition(question.question == "An enrichment question")
        precondition(question.breed == "Fictional mix")
        precondition(record["conversationStatus"] == nil)
        print("ClientQuestion compatibility, display, and update checks passed")
    }
}
