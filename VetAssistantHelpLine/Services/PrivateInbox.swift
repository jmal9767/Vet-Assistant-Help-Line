import Foundation
import LocalAuthentication
import Security
import SwiftUI

struct InboxCredentials: Codable {
    let baseURL: URL
    let token: String
    static func validate(url: String, token: String) throws -> Self {
        guard let value = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.scheme == "https", value.host != nil, value.user == nil,
              value.password == nil, value.query == nil, value.fragment == nil,
              value.path.isEmpty || value.path == "/",
              token.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
            throw InboxError.message("Use the HTTPS service URL and the 64-character private device key supplied during server setup. This is not your Stripe key.")
        }
        return Self(baseURL: value, token: token)
    }
}

enum DeviceKeychain {
    static let service = "com.bayareaapps.vetassistanthelpline.operator"
    static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "private-inbox"]
    }
    static func read() throws -> InboxCredentials? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw InboxError.message("The private device key is unavailable. Unlock your phone and try again.")
        }
        return try JSONDecoder().decode(InboxCredentials.self, from: data)
    }
    static func save(_ credentials: InboxCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw InboxError.message("Could not securely save the device key.") }
    }
    static func remove() { SecItemDelete(query as CFDictionary) }
}

final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class PrivateInbox: ObservableObject {
    private struct Failure: Decodable { let error: String }
    @Published private(set) var catalog: ServiceCatalog?
    @Published private(set) var questions: [OperatorQuestion] = []
    @Published private(set) var unlocked = false
    @Published private(set) var accepting = false
    @Published private(set) var live = false
    @Published private(set) var busy = false
    @Published var error: String?
    private var credentials: InboxCredentials?
    private var generation = UUID()
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        do { catalog = try ServiceCatalog.bundled() } catch { self.error = error.localizedDescription }
    }

    func unlock(url: String = "", token: String = "") async {
        guard !busy else { return }
        busy = true; error = nil
        let attempt = generation
        defer { busy = false }
        do {
            let context = LAContext()
            guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
                throw InboxError.message("Set a passcode on this iPhone before opening the private inbox.")
            }
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Open your private paid-question inbox") else { return }
            guard attempt == generation else { return }
            let saved = try DeviceKeychain.read()
            let resolved: InboxCredentials
            if !url.isEmpty || !token.isEmpty { resolved = try InboxCredentials.validate(url: url, token: token) }
            else if let saved { resolved = saved }
            else { throw InboxError.message("Enter your service URL and private device key to connect for the first time.") }
            credentials = resolved
            let remote: ServiceCatalog = try await request("api/admin/catalog")
            let inbox: InboxResponse = try await request("api/admin/questions")
            guard attempt == generation else { return }
            try DeviceKeychain.save(resolved)
            catalog = remote; questions = inbox.questions; accepting = inbox.accepting; live = inbox.live
            unlocked = true
        } catch {
            credentials = nil
            if attempt == generation { self.error = error.localizedDescription }
        }
    }

    func lock() {
        generation = UUID(); credentials = nil; questions = []; unlocked = false
        error = nil
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
    }

    func disconnect() { lock(); DeviceKeychain.remove() }

    func refresh() async {
        guard unlocked, !busy else { return }
        busy = true; error = nil
        let attempt = generation
        defer { busy = false }
        do {
            let inbox: InboxResponse = try await request("api/admin/questions")
            guard attempt == generation, unlocked else { return }
            questions = inbox.questions; accepting = inbox.accepting; live = inbox.live
        } catch { if attempt == generation { self.error = error.localizedDescription } }
    }

    func setAvailability(_ value: Bool) async {
        do {
            struct Availability: Decodable { let accepting: Bool }
            let response: Availability = try await request("api/admin/availability", body: ["accepting": value])
            guard unlocked else { return }; accepting = response.accepting
        } catch { self.error = error.localizedDescription }
    }

    func act(_ question: OperatorQuestion, action: String, values: [String: Any] = [:]) async throws -> OperatorQuestion {
        guard unlocked else { throw InboxError.message("Unlock the inbox first.") }
        let attempt = generation
        var payload = values; payload["version"] = question.version
        let updated: OperatorQuestion = try await request("api/admin/questions/\(question.id)/\(action)", body: payload)
        guard attempt == generation, unlocked else { throw CancellationError() }
        if let index = questions.firstIndex(where: { $0.id == updated.id }) { questions[index] = updated }
        return updated
    }

    private func request<T: Decodable>(_ path: String, body: [String: Any]? = nil) async throws -> T {
        guard let credentials else { throw InboxError.message("Connect your private inbox first.") }
        var request = URLRequest(url: credentials.baseURL.appendingPathComponent(path))
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data).error) ?? "The inbox could not be reached securely. Check the service URL and device key."
            throw InboxError.message(message)
        }
        let decoder = JSONDecoder()
        if T.self != ServiceCatalog.self { decoder.keyDecodingStrategy = .convertFromSnakeCase }
        return try decoder.decode(T.self, from: data)
    }
}
