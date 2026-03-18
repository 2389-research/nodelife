// ABOUTME: Thin wrapper around macOS Security framework for keychain access.
// ABOUTME: Provides save, retrieve, and delete operations for API keys.

import Foundation
import Security

public struct KeychainService: Sendable {
    private let serviceName: String

    public init(serviceName: String = "com.nodelife.app") {
        self.serviceName = serviceName
    }

    public func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecDuplicateItem {
                // Item was added concurrently; retry as update
                let retryStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
                guard retryStatus == errSecSuccess else {
                    throw KeychainError.saveFailed(status: retryStatus)
                }
            } else if addStatus != errSecSuccess {
                throw KeychainError.saveFailed(status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.saveFailed(status: updateStatus)
        }
    }

    public func retrieve(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.retrieveFailed(status: status)
        }

        guard let data = result as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.retrieveFailed(status: status)
        }

        return string
    }

    public func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }
    }

    public enum KeychainError: Error, LocalizedError, Sendable {
        case encodingFailed
        case saveFailed(status: OSStatus)
        case retrieveFailed(status: OSStatus)
        case deleteFailed(status: OSStatus)

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode value as UTF-8 data"
            case .saveFailed(let status):
                return "Keychain save failed with status \(status)"
            case .retrieveFailed(let status):
                return "Keychain retrieve failed with status \(status)"
            case .deleteFailed(let status):
                return "Keychain delete failed with status \(status)"
            }
        }
    }
}
