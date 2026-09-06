import Foundation

struct ServiceCategory: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let prompt: String
    let contextPrompt: String
    let examples: [String]
    let notIncluded: String
    let answerGoal: String
    let sources: [String]
}

struct ServiceCatalog: Codable {
    struct Screening: Codable, Identifiable { let id: String; let text: String }
    struct FreeHelp: Codable { let title: String; let answer: String }
    let version: String
    let serviceName: String
    let operatorName: String
    let supportEmail: String
    let priceCents: Int
    let currency: String
    let clarificationDays: Int
    let responseBusinessDays: Int
    let scope: String
    let responsePromise: String
    let coverage: String
    let refundPolicy: String
    let emergency: String
    let privacyHint: String
    let screening: [Screening]
    let categories: [ServiceCategory]
    let freeHelp: [FreeHelp]
    let answerChecklist: [String]

    var price: String {
        (Double(priceCents) / 100).formatted(.currency(code: currency.uppercased()))
    }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "service-catalog", withExtension: "json") else {
            throw InboxError.message("The service catalog is missing. Rebuild the app before accepting questions.")
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
