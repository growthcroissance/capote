import Foundation
import XCTest
@testable import CapoteRemoteCore

final class RemoteControlCoreTests: XCTestCase {
    func testTailscaleAddressesAreNormalizedFailClosed() {
        XCTAssertEqual(RemoteDirectAccess.port, 51_684)
        XCTAssertEqual(
            RemoteDirectAccess.normalizedTailscaleHost("  MAC.PERSO.TS.NET. "),
            "mac.perso.ts.net"
        )
        XCTAssertEqual(RemoteDirectAccess.normalizedTailscaleHost("100.64.0.1"), "100.64.0.1")
        XCTAssertEqual(RemoteDirectAccess.normalizedTailscaleHost("100.127.255.254"), "100.127.255.254")
        XCTAssertEqual(
            RemoteDirectAccess.normalizedTailscaleHost("[fd7a:115c:a1e0::1]"),
            "fd7a:115c:a1e0::1"
        )

        XCTAssertNil(RemoteDirectAccess.normalizedTailscaleHost("mac"))
        XCTAssertNil(RemoteDirectAccess.normalizedTailscaleHost("example.com"))
        XCTAssertNil(RemoteDirectAccess.normalizedTailscaleHost("192.168.1.10"))
        XCTAssertNil(RemoteDirectAccess.normalizedTailscaleHost("100.128.0.1"))
        XCTAssertNil(RemoteDirectAccess.normalizedTailscaleHost("-mac.perso.ts.net"))
    }

    func testTailscaleIPv4IsExtractedFromCLIOutput() {
        XCTAssertEqual(
            RemoteDirectAccess.firstTailscaleIPv4(in: "100.99.88.77\n"),
            "100.99.88.77"
        )
        XCTAssertEqual(
            RemoteDirectAccess.firstTailscaleIPv4(in: "warning\n100.64.0.1 extra"),
            "100.64.0.1"
        )
        XCTAssertNil(RemoteDirectAccess.firstTailscaleIPv4(in: "192.168.1.4\nexample.com"))
    }

    func testLegacyRemoteStatusDecodesWithoutTailscaleHost() throws {
        let legacyJSON = Data(
            """
            {
              "isSleepDisabled": false,
              "canRestoreActiveSession": false,
              "activeSessionDescription": null,
              "sessionEndDate": null,
              "thermalSafetyTriggered": false
            }
            """.utf8
        )

        let status = try JSONDecoder.capoteRemote.decode(RemoteMacStatus.self, from: legacyJSON)
        XCTAssertEqual(status.isSleepDisabled, false)
        XCTAssertFalse(status.canRestoreActiveSession)
        XCTAssertNil(status.thermalState)
        XCTAssertNil(status.tailscaleHost)
    }

    func testRemoteStatusRoundTripsThermalState() throws {
        let status = RemoteMacStatus(
            isSleepDisabled: true,
            canRestoreActiveSession: true,
            activeSessionDescription: "Session active",
            sessionEndDate: nil,
            thermalState: .serious
        )

        let data = try JSONEncoder.capoteRemote.encode(status)
        let decoded = try JSONDecoder.capoteRemote.decode(RemoteMacStatus.self, from: data)

        XCTAssertEqual(decoded.thermalState, .serious)
    }

    func testLocalRouteIsPreferredWhenAvailable() {
        XCTAssertEqual(
            RemoteDirectAccess.preferredRoutes(hasTailscaleHost: true, hasLocalEndpoint: true),
            [.localNetwork, .tailscale]
        )
        XCTAssertEqual(
            RemoteDirectAccess.preferredRoutes(hasTailscaleHost: false, hasLocalEndpoint: true),
            [.localNetwork]
        )
        XCTAssertEqual(
            RemoteDirectAccess.preferredRoutes(hasTailscaleHost: true, hasLocalEndpoint: false),
            [.tailscale]
        )
    }

    func testCompanionSelectionFallsBackWhenPersistedMacWasRemoved() {
        let removedIdentifier = UUID()
        let remainingIdentifier = UUID()

        XCTAssertEqual(
            CompanionSelectionPolicy.selectedIdentifier(
                persistedIdentifier: removedIdentifier,
                availableIdentifiers: [remainingIdentifier]
            ),
            remainingIdentifier
        )
        XCTAssertEqual(
            CompanionSelectionPolicy.selectedIdentifier(
                persistedIdentifier: remainingIdentifier,
                availableIdentifiers: [remainingIdentifier, UUID()]
            ),
            remainingIdentifier
        )
        XCTAssertNil(
            CompanionSelectionPolicy.selectedIdentifier(
                persistedIdentifier: removedIdentifier,
                availableIdentifiers: []
            )
        )
    }

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
