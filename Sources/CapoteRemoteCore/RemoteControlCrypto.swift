import CryptoKit
import Foundation
import Security

public enum RemoteCryptoError: Error, Equatable {
    case randomGenerationFailed
    case invalidPairingCode
    case invalidProof
    case invalidSealedPayload
}

public enum RemoteControlCrypto {
    public static func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RemoteCryptoError.randomGenerationFailed
        }
        return Data(bytes)
    }

    public static func makePairingCode() throws -> String {
        let bytes = try randomData(count: 12)
        let hex = bytes.map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: hex.count, by: 4).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: min(4, hex.distance(from: start, to: hex.endIndex)))
            return String(hex[start..<end])
        }.joined(separator: "-")
    }

    public static func normalizedPairingCode(_ code: String) throws -> Data {
        let hex = code.uppercased().filter { $0.isHexDigit }
        guard hex.count == 24 else { throw RemoteCryptoError.invalidPairingCode }

        var bytes = [UInt8]()
        bytes.reserveCapacity(12)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else {
                throw RemoteCryptoError.invalidPairingCode
            }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    public static func pairingProof(
        pairingCode: String,
        serviceIdentifier: UUID,
        deviceIdentifier: UUID,
        deviceName: String,
        nonce: Data
    ) throws -> Data {
        let key = SymmetricKey(data: try normalizedPairingCode(pairingCode))
        var authenticatedData = Data("capote-pair-v1".utf8)
        authenticatedData.append(Data(serviceIdentifier.uuidString.utf8))
        authenticatedData.append(Data(deviceIdentifier.uuidString.utf8))
        authenticatedData.append(Data(deviceName.utf8))
        authenticatedData.append(nonce)
        return Data(HMAC<SHA256>.authenticationCode(for: authenticatedData, using: key))
    }

    public static func verifyPairRequest(_ request: PairRequest, pairingCode: String) throws {
        guard request.protocolVersion == CapoteRemoteProtocol.version,
              request.deviceName.count <= 80,
              request.nonce.count == 16 else {
            throw RemoteCryptoError.invalidProof
        }
        let expected = try pairingProof(
            pairingCode: pairingCode,
            serviceIdentifier: request.serviceIdentifier,
            deviceIdentifier: request.deviceIdentifier,
            deviceName: request.deviceName,
            nonce: request.nonce
        )
        guard constantTimeEqual(expected, request.proof) else {
            throw RemoteCryptoError.invalidProof
        }
    }

    public static func sealDeviceKey(_ deviceKey: Data, pairingCode: String, nonce: Data) throws -> Data {
        let wrappingKey = try derivePairingKey(pairingCode: pairingCode, nonce: nonce)
        return try seal(deviceKey, using: wrappingKey)
    }

    public static func openDeviceKey(_ sealed: Data, pairingCode: String, nonce: Data) throws -> Data {
        let wrappingKey = try derivePairingKey(pairingCode: pairingCode, nonce: nonce)
        return try open(sealed, using: wrappingKey)
    }

    public static func seal<T: Encodable>(_ value: T, using keyData: Data) throws -> Data {
        let encoded = try JSONEncoder.capoteRemote.encode(value)
        return try seal(encoded, using: SymmetricKey(data: keyData))
    }

    public static func open<T: Decodable>(_ type: T.Type, from sealed: Data, using keyData: Data) throws -> T {
        let clear = try open(sealed, using: SymmetricKey(data: keyData))
        return try JSONDecoder.capoteRemote.decode(type, from: clear)
    }

    private static func derivePairingKey(pairingCode: String, nonce: Data) throws -> SymmetricKey {
        let input = try normalizedPairingCode(pairingCode)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: input),
            salt: nonce,
            info: Data("capote-pairing-key-v1".utf8),
            outputByteCount: 32
        )
    }

    private static func seal(_ clear: Data, using key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(clear, using: key).combined
    }

    private static func open(_ sealed: Data, using key: SymmetricKey) throws -> Data {
        do {
            return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: key)
        } catch {
            throw RemoteCryptoError.invalidSealedPayload
        }
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }
}

public extension JSONEncoder {
    static var capoteRemote: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var capoteRemote: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
