import Foundation

struct CareLineMessage: Codable, Identifiable { let id: String; let sender: String; let text: String; let createdAt: String }
struct CareLineThread: Decodable {
    let token: String
    let petName: String
    let question: String
    let service: String
    let paymentStatus: String
    let messages: [CareLineMessage]
    let conversationURL: String?
    var privateURL: URL? {
        guard let value = conversationURL, let url = URL(string: value), url.scheme == "https", url.host == "paws-whiskers-care-line.dkjmmz6whh.workers.dev", url.path == "/conversation.html", url.query == nil, url.user == nil, url.password == nil, url.port == nil,
              let fragment = url.fragment, fragment.range(of: "^thread=[a-f0-9]{32}\\.[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return url
    }
}
struct CareLineConversationService {
    private struct Connection: Decodable { let connectionKey: String }
    func perform<T: Decodable>(_ path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        var proof = URLRequest(url: HelplineConfig.checkoutBaseURL.appendingPathComponent("careline/device-connection"))
        proof.httpMethod = "POST"; proof.timeoutInterval = 30
        proof.setValue("application/json", forHTTPHeaderField: "Content-Type")
        proof.httpBody = try JSONEncoder().encode(CareLineDeviceIdentity.proof())
        let (data, response) = try await URLSession.shared.data(for: proof)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw failure("Help Line replies could not connect on this iPhone. Check your connection and retry.") }
        let key = try JSONDecoder().decode(Connection.self, from: data).connectionKey
        guard key.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw failure("Help Line access could not be verified.") }
        var request = URLRequest(url: HelplineConfig.checkoutBaseURL.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 30; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONEncoder().encode(body) }
        let (result, resultResponse) = try await URLSession.shared.data(for: request)
        guard let status = resultResponse as? HTTPURLResponse, (200..<300).contains(status.statusCode) else {
            throw failure((try? JSONSerialization.jsonObject(with: result) as? [String: String])?["error"] ?? "The conversation could not load. Retry; your message stays here.")
        }
        return try JSONDecoder().decode(T.self, from: result)
    }
    func verifyConnection() async throws {
        struct Status: Decodable { let ok: Bool }
        let result: Status = try await perform("careline/operator/status")
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("careline-access-status.json")
        try JSONEncoder().encode(["authorized": result.ok]).write(to: file, options: .atomic)
    }
    func thread(_ token: String) async throws -> CareLineThread { try await perform("careline/operator/threads/" + token) }
    func send(_ text: String, id: String, token: String) async throws -> CareLineThread { try await perform("careline/operator/threads/" + token + "/messages", method: "POST", body: ["text":text,"id":id]) }
    func create(recordName: String) async throws -> CareLineThread { try await perform("careline/operator/questions/" + recordName + "/conversation", method: "POST", body: [:]) }
    func remove(_ token: String) async throws {
        struct Result: Decodable { let ok: Bool }
        let _: Result = try await perform("careline/operator/threads/" + token, method: "DELETE")
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "CareLineConversation", code: 1, userInfo: [NSLocalizedDescriptionKey:text]) }
}
