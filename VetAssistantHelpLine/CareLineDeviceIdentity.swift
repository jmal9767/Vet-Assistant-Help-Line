import Foundation
import CryptoKit
import Security

enum CareLineDeviceIdentity {
    private static let account = "owner-device-signing-key"
    private static let service = "com.bayareaapps.paws-care-line"
    struct Proof: Encodable {
        let publicKey: String
        let nonce: String
        let timestamp: String
        let signature: String
    }
    static func proof() throws -> Proof {
        let data = try signingKeyData()
        #if targetEnvironment(simulator)
        let key = try P256.Signing.PrivateKey(rawRepresentation: data)
        #else
        let key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        #endif
        let publicKey = key.publicKey.x963Representation.base64EncodedString()
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("careline-device-public-key.txt")
        try Data(publicKey.utf8).write(to: file, options: .atomic)
        return try signedProof(publicKey: publicKey) { try key.signature(for: $0).rawRepresentation }
    }
    static func signedProof(publicKey: String, sign: (Data) throws -> Data) throws -> Proof {
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let message = Data(("PawsCareLineDevice/v1\n" + publicKey + "\n" + nonce + "\n" + timestamp).utf8)
        return Proof(publicKey: publicKey, nonce: nonce, timestamp: timestamp, signature: try sign(message).base64EncodedString())
    }
    private static func signingKeyData() throws -> Data {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        var read = query; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &value)
        if status == errSecSuccess, let data = value as? Data { return data }
        guard status == errSecItemNotFound else { throw failure() }
        #if targetEnvironment(simulator)
        let data = P256.Signing.PrivateKey().rawRepresentation
        #else
        let data = try SecureEnclave.P256.Signing.PrivateKey().dataRepresentation
        #endif
        var entry = query; entry[kSecValueData as String] = data; entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw failure() }
        return data
    }
    private static func failure() -> NSError { NSError(domain: "BusinessDevice", code: 1, userInfo: [NSLocalizedDescriptionKey: "Your iPhone’s business access could not open. Unlock the phone and try again."]) }
}
