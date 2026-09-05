import Foundation

struct QuestionEmail: Equatable, Sendable {
    let recipient: String
    let subject: String
    let body: String

    var clipboardText: String {
        """
        To: \(recipient)
        Subject: \(subject)

        \(body)
        """
    }

    var fallbackMailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject)
        ]
        return components.url
    }
}

enum EmailCompletionKind: Sendable {
    case appleMailQueued
    case fallbackConfirmedSent
    case handoffReconciledAsSent
}
