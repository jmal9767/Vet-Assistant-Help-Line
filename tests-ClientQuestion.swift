import Foundation
import CloudKit

@main
struct VerifyClientQuestion {
    static func main() throws {
        let record = CKRecord(recordType: "Question", recordID: CKRecord.ID(recordName: "fictional-test"))
        record["name"] = "Fictional operator test"
        let body: [String: Any] = ["format": "paws-intake-v1", "question": "An enrichment question", "details": ["breed": "Fictional mix", "paymentAmount": "$0", "paymentStatus": "No payment required", "signedConsentName": "Fictional test", "conversationStatus": "Needs response", "conversationToken": String(repeating: "a", count: 32)]]
        record["question"] = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        let question = ClientQuestion(record: record)
        precondition(question.conversationToken == String(repeating: "a", count: 32))
        precondition(question.question == "An enrichment question")
        precondition(question.breed == "Fictional mix")
        precondition(question.paymentAmount == "$0")
        precondition(question.signedConsentName == "Fictional test")
        question.setString("Closed", for: "conversationStatus")
        precondition(question.conversationStatus == "Closed")
        precondition(question.question == "An enrichment question")
        precondition(question.breed == "Fictional mix")
        precondition(record["conversationStatus"] == nil)
        let freeRecord = CKRecord(recordType: "Question")
        freeRecord["requestedService"] = "Free Community Support — Email"
        precondition(ClientQuestion(record: freeRecord).paymentAmount == "$0")
        freeRecord["requestedService"] = "Community Access — Text · $0"
        precondition(ClientQuestion(record: freeRecord).requestedService == "Free Community Support — Text")
        precondition(ClientQuestion(record: freeRecord).paymentAmount == "$0")
        freeRecord["paymentAmount"] = "$35"
        precondition(ClientQuestion(record: freeRecord).paymentAmount == "$35")
        for packed in [false, true] {
            for approved in [false, true] {
                let decision = CKRecord(recordType: "Question")
                decision["status"] = "new"
                if packed {
                    decision["question"] = "{\"format\":\"paws-intake-v1\",\"question\":\"Pet enrichment\",\"details\":{\"paymentStatus\":\"Awaiting approval\",\"conversationStatus\":\"Awaiting approval\",\"conversationToken\":\"private-token\"}}"
                } else {
                    decision["question"] = "Pet enrichment"
                    decision["paymentStatus"] = "Awaiting approval"
                    decision["conversationStatus"] = "Awaiting approval"
                }
                let item = ClientQuestion(record: decision)
                precondition(item.canDecideAvailability)
                try item.recordAvailabilityDecision(approved: approved)
                precondition(item.paymentStatus == (approved ? "Payment requested" : "Declined — no charge"))
                precondition(item.status == (approved ? .new : .archived))
                precondition(item.question == "Pet enrichment")
                if packed { precondition(decision["paymentStatus"] == nil) }
                do { try item.recordAvailabilityDecision(approved: !approved); fatalError("Repeated decision changed the request") } catch { }
            }
        }
        for payment in ["Paid", "No payment required", "Refunded", "Payment pending"] {
            let item = CKRecord(recordType: "Question"); item["paymentStatus"] = payment
            do { try ClientQuestion(record: item).recordAvailabilityDecision(approved: true); fatalError("Approval changed an ineligible request") } catch { }
        }
        print("ClientQuestion compatibility, display, and update checks passed")
    }
}
