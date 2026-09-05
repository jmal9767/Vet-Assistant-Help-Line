import Foundation

struct PaidQuestionCredit: Identifiable, Equatable, Sendable {
    let id: UInt64
    let productID: String
    let purchaseDate: Date
    let appAccountToken: UUID?
    let environment: String
    let signedTransactionJWS: String
}

enum PurchaseOutcome: Equatable, Sendable {
    case verified(PaidQuestionCredit)
    case pending
    case cancelled
    case failed(String)
}
