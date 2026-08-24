import Foundation
import Security

struct PairedRemoteDevice: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var pairedAt: Date
}

final class RemoteDeviceKeyStore: @unchecked Sendable {
    private let service = "fr.benjaminfarrudja.capote.remote-device-key"
    private let defaultsKey = "remoteControl.pairedDevices"
    private let lock = NSLock()

    func save(key: Data, for device: PairedRemoteDevice) throws {
        lock.lock()
        defer { lock.unlock() }

        let account = device.id.uuidString
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: key] as CFDictionary
        )
        if updateStatus == errSecItemNotFound {
            var insert = baseQuery
            insert[kSecValueData as String] = key
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
                throw RemoteKeyStoreError.writeFailed
            }
        } else if updateStatus != errSecSuccess {
            throw RemoteKeyStoreError.writeFailed
        }

        var devices = loadDevicesUnlocked().filter { $0.id != device.id }
        devices.append(device)
        try saveDevicesUnlocked(devices)
    }

    func key(for deviceIdentifier: UUID) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceIdentifier.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else {
            return nil
        }
        return result as? Data
    }

    func devices() -> [PairedRemoteDevice] {
        lock.lock()
        defer { lock.unlock() }
        return loadDevicesUnlocked().sorted { $0.pairedAt < $1.pairedAt }
    }

    func remove(deviceIdentifier: UUID) {
        lock.lock()
        defer { lock.unlock() }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceIdentifier.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        try? saveDevicesUnlocked(loadDevicesUnlocked().filter { $0.id != deviceIdentifier })
    }

    private func loadDevicesUnlocked() -> [PairedRemoteDevice] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder.capoteRemote.decode([PairedRemoteDevice].self, from: data)) ?? []
    }

    private func saveDevicesUnlocked(_ devices: [PairedRemoteDevice]) throws {
        UserDefaults.standard.set(try JSONEncoder.capoteRemote.encode(devices), forKey: defaultsKey)
    }
}

enum RemoteKeyStoreError: Error {
    case writeFailed
}
