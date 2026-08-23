import Foundation
import XCTest
@testable import CapoteRemoteCore

final class RemoteControlCoreTests: XCTestCase {
    func testPairingProofAndWrappedDeviceKeyRoundTrip() throws {
        let code = try RemoteControlCrypto.makePairingCode()
        let serviceID = UUID()
        let deviceID = UUID()
        let nonce = try RemoteControlCrypto.randomData(count: 16)
        let proof = try RemoteControlCrypto.pairingProof(
            pairingCode: code,
            serviceIdentifier: serviceID,
            deviceIdentifier: deviceID,
            deviceName: "iPhone de test",
            nonce: nonce
        )
        let request = PairRequest(
            serviceIdentifier: serviceID,
            deviceIdentifier: deviceID,
            deviceName: "iPhone de test",
            nonce: nonce,
            proof: proof
        )

        XCTAssertNoThrow(try RemoteControlCrypto.verifyPairRequest(request, pairingCode: code))

        let deviceKey = try RemoteControlCrypto.randomData(count: 32)
        let sealed = try RemoteControlCrypto.sealDeviceKey(deviceKey, pairingCode: code, nonce: nonce)
        XCTAssertEqual(
            try RemoteControlCrypto.openDeviceKey(sealed, pairingCode: code, nonce: nonce),
            deviceKey
        )
    }

    func testWrongPairingCodeIsRejected() throws {
        let serviceID = UUID()
        let deviceID = UUID()
        let nonce = try RemoteControlCrypto.randomData(count: 16)
        let request = PairRequest(
            serviceIdentifier: serviceID,
            deviceIdentifier: deviceID,
            deviceName: "iPhone de test",
            nonce: nonce,
            proof: try RemoteControlCrypto.pairingProof(
                pairingCode: "AAAA-BBBB-CCCC-DDDD-EEEE-FFFF",
                serviceIdentifier: serviceID,
                deviceIdentifier: deviceID,
                deviceName: "iPhone de test",
                nonce: nonce
            )
        )

        XCTAssertThrowsError(
            try RemoteControlCrypto.verifyPairRequest(
                request,
                pairingCode: "1111-2222-3333-4444-5555-6666"
            )
        )
    }

    func testEncryptedCommandAndFrameRoundTrip() throws {
        let key = try RemoteControlCrypto.randomData(count: 32)
        let command = RemoteCommand(action: .status)
        let encrypted = EncryptedRemotePayload(
            deviceIdentifier: UUID(),
            sealedPayload: try RemoteControlCrypto.seal(command, using: key)
        )
        let wire = RemoteWireMessage(
            kind: .command,
            payload: try JSONEncoder.capoteRemote.encode(encrypted)
        )

        let decodedWire = try RemoteFrameCodec.decode(RemoteFrameCodec.encode(wire))
        let decodedEncrypted = try JSONDecoder.capoteRemote.decode(
            EncryptedRemotePayload.self,
            from: decodedWire.payload
        )
        let decodedCommand = try RemoteControlCrypto.open(
            RemoteCommand.self,
            from: decodedEncrypted.sealedPayload,
            using: key
        )

        XCTAssertEqual(decodedCommand.identifier, command.identifier)
        XCTAssertEqual(decodedCommand.action, command.action)
    }

    func testValidatorRejectsReplay() throws {
        XCTAssertEqual(
            RemoteCommandAction.allCases.map(\.rawValue),
            ["status", "restoreSleep"]
        )

        let now = Date()
        let validator = RemoteCommandValidator()
        let command = RemoteCommand(issuedAt: now, action: .status)

        XCTAssertNoThrow(try validator.validate(command, now: now))
        XCTAssertThrowsError(try validator.validate(command, now: now)) { error in
            XCTAssertEqual(error as? RemoteCommandValidationError, .replayed)
        }
    }

    func testTamperedCiphertextIsRejected() throws {
        let key = try RemoteControlCrypto.randomData(count: 32)
        var sealed = try RemoteControlCrypto.seal(RemoteCommand(action: .status), using: key)
        sealed[sealed.startIndex] ^= 0x01
        XCTAssertThrowsError(
            try RemoteControlCrypto.open(RemoteCommand.self, from: sealed, using: key)
        ) { error in
            XCTAssertEqual(error as? RemoteCryptoError, .invalidSealedPayload)
        }
    }

    func testExpiredCommandIsRejected() {
        let command = RemoteCommand(
            issuedAt: Date().addingTimeInterval(-60),
            lifetime: 30,
            action: .status
        )
        XCTAssertThrowsError(try RemoteCommandValidator().validate(command)) { error in
            XCTAssertEqual(error as? RemoteCommandValidationError, .expired)
        }
    }
}
