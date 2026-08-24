import Foundation
import Security

final class CompanionKeyStore {
    private let service = "fr.benjaminfarrudja.capote.companion.mac-key"

    func save(key: Data, for macIdentifier: UUID) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: macIdentifier.uuidString
        ]
        let status = SecItemUpdate(
            base as CFDictionary,
            [kSecValueData as String: key] as CFDictionary
        )
        if status == errSecItemNotFound {
            var insert = base
            insert[kSecValueData as String] = key
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw CompanionKeyStoreError.writeFailed
            }
        } else if status != errSecSuccess {
            throw CompanionKeyStoreError.writeFailed
        }
    }

    func key(for macIdentifier: UUID) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: macIdentifier.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func remove(for macIdentifier: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: macIdentifier.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private enum CompanionKeyStoreError: Error {
    case writeFailed
}
