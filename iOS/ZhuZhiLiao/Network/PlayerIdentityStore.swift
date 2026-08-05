import Foundation
import Security

struct PlayerIdentity: Codable, Equatable, Sendable {
    let id: String
    let code: String
    let token: String
}

enum PlayerIdentityStoreError: Error {
    case keychain(OSStatus)
    case invalidData
}

final class PlayerIdentityStore: @unchecked Sendable {
    private let service: String
    private let account = "anonymous-leaderboard-player"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.azhegezhege.zhuzhiliao") {
        self.service = service
    }

    func load() throws -> PlayerIdentity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw PlayerIdentityStoreError.keychain(status)
        }
        guard let data = result as? Data,
              let identity = try? JSONDecoder().decode(PlayerIdentity.self, from: data) else {
            throw PlayerIdentityStoreError.invalidData
        }
        return identity
    }

    func save(_ identity: PlayerIdentity) throws {
        let data = try JSONEncoder().encode(identity)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw PlayerIdentityStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        attributes.forEach { item[$0.key] = $0.value }
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw PlayerIdentityStoreError.keychain(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PlayerIdentityStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
