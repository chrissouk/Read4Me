import Foundation
import Security
import Combine

@MainActor
protocol APIKeyProviding {
    func load() throws -> String?
}

@MainActor
final class APIKeyStore: ObservableObject, APIKeyProviding {
    @Published private(set) var hasKey = false
    @Published private(set) var error: String?
    private let service: String
    private let account = "OpenAIAPIKey"

    init(service: String = "com.chrissouk.Read4Me.OpenAI") {
        self.service = service
        do { hasKey = try load() != nil }
        catch { self.error = error.localizedDescription }
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else { throw KeychainError(status: status) }
        return key
    }

    func save(_ input: String) throws {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw SpeechError.missingKey }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let item = query.merging(attributes) { _, value in value }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        hasKey = true
        error = nil
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
        hasKey = false
        error = nil
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Could not access the securely stored API key (\(status))." }
}
