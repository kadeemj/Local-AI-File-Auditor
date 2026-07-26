import Foundation
import Security

/// Thin Keychain wrapper. Production uses the real keychain; tests inject `InMemorySecureStore`.
protocol SecureStore: Sendable {
    func data(forKey key: String) throws -> Data?
    func setData(_ data: Data?, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

enum SecureStoreError: Error, Sendable, Equatable {
    case unexpectedStatus(OSStatus)
}

struct KeychainStore: SecureStore {
    let service: String

    init(service: String = "com.folderlint.app.licensing") {
        self.service = service
    }

    func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecureStoreError.unexpectedStatus(status) }
        return item as? Data
    }

    func setData(_ data: Data?, forKey key: String) throws {
        if data == nil {
            try removeValue(forKey: key)
            return
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data as Any]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else { throw SecureStoreError.unexpectedStatus(updateStatus) }
        } else if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data as Any
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw SecureStoreError.unexpectedStatus(addStatus) }
        } else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }

    func removeValue(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureStoreError.unexpectedStatus(status)
        }
    }
}

/// Process-local store for unit tests — never touches the system keychain.
final class InMemorySecureStoreBox: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    func setData(_ data: Data?, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        if let data {
            storage[key] = data
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func removeValue(forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}
