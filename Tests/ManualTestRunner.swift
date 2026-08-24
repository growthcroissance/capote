import Foundation
import ServiceManagement

@main @MainActor
struct ManualTestRunner {
    static func main() {
        testEnabledState()
        testDisabledState()
        testMissingState()
        testDurationArguments()
        testDownloadArguments()
        testThermalTerminationReasons()
        testCommandEscaping()
        testVersionComparison()
        testOfficialUpdateValidation()
        testUnsafeUpdateRejection()
        testSessionRecoveryPolicy()
        testMissingLaunchAtLoginRecord()
        testLaunchAtLoginController()
        testRemotePairingAndEncryption()
        testRemoteCommandValidation()
        testRemoteFrameCodec()
        testRemoteTamperRejection()
        testRemoteExpiredCommandRejection()
        testTailscaleAddressValidation()
        testTailscaleRoutePreference()
        print("20 tests réussis")
    }

    private static func testEnabledState() {
        expect(
            SleepDisabledState.parse(pmsetOutput: "System-wide power settings:\n SleepDisabled 1\n") == true,
            "lecture de l’état activé"
        )
    }

    private static func testDisabledState() {
        expect(
            SleepDisabledState.parse(pmsetOutput: "System-wide power settings:\n SleepDisabled 0\n") == false,
            "lecture de l’état désactivé"
        )
    }

    private static func testMissingState() {
        expect(
            SleepDisabledState.parse(pmsetOutput: "sleep 1\n") == nil,
            "rejet d’un état absent"
        )
    }

    private static func testDurationArguments() {
        let cancelURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-test.cancel")
        let resultURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-test.result")
        let arguments = SessionRequest.duration(300).helperArguments(cancelURL: cancelURL, resultURL: resultURL)

        expect(arguments.contains("duration"), "arguments du mode durée")
        expect(arguments.contains("300.0"), "durée transmise au helper")
        expect(arguments.contains("--user-uid"), "identité utilisateur transmise au helper")
    }

    private static func testDownloadArguments() {
        let cancelURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-test.cancel")
        let resultURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-test.result")
        let arguments = SessionRequest.download(
            path: "/tmp/fichier avec espaces.download",
            stableSeconds: 10
        ).helperArguments(cancelURL: cancelURL, resultURL: resultURL)

        expect(arguments.contains("download"), "arguments du mode téléchargement")
        expect(!arguments.contains("/tmp/fichier avec espaces.download"), "chemin encodé en base64")
    }

    private static func testThermalTerminationReasons() {
        expect(
            SessionTerminationReason.parse(Data("thermal-serious\n".utf8)) == .thermalSerious,
            "lecture de l’arrêt thermique sérieux"
        )
        expect(
            SessionTerminationReason.parse(Data("thermal-critical".utf8)) == .thermalCritical,
            "lecture de l’arrêt thermique critique"
        )
        expect(SessionTerminationReason.parse(Data("duration".utf8)) == nil, "rejet d’un motif inconnu")
    }

    private static func testCommandEscaping() {
        let shellQuoted = SessionCommandEscaping.shellQuote("/tmp/L'app Capote")
        let appleScriptQuoted = SessionCommandEscaping.appleScriptLiteral("commande \"test\"")

        expect(shellQuoted == "'/tmp/L'\"'\"'app Capote'", "échappement shell du chemin")
        expect(appleScriptQuoted == "commande \\\"test\\\"", "échappement de la chaîne AppleScript")
    }

    private static func testVersionComparison() {
        expect(AppVersion("1.2.0")! > AppVersion("1.1.9")!, "comparaison SemVer")
        expect(AppVersion("v2.0.0") == AppVersion("2.0.0"), "préfixe de tag accepté")
        expect(AppVersion("1.2") == nil, "version incomplète rejetée")
        expect(AppVersion("1.2.0-beta") == nil, "préversion rejetée")
        expect(AppVersion("01.2.0") == nil, "zéro initial rejeté")
    }

    private static func testOfficialUpdateValidation() {
        let release = GitHubRelease(
            tagName: "v1.1.0",
            htmlURL: URL(string: "https://github.com/growthcroissance/capote/releases/tag/v1.1.0")!,
            isDraft: false,
            isPrerelease: false
        )
        let update = try? AppUpdatePolicy.availableUpdate(currentVersion: "1.0.1", release: release)
        let currentRelease = try? AppUpdatePolicy.availableUpdate(
            currentVersion: "1.1.0",
            release: release
        )

        expect(update?.version == AppVersion("1.1.0"), "mise à jour officielle détectée")
        expect(currentRelease == nil, "version courante non reproposée")
    }

    private static func testUnsafeUpdateRejection() {
        let release = GitHubRelease(
            tagName: "v9.0.0",
            htmlURL: URL(string: "https://example.com/capote.zip")!,
            isDraft: false,
            isPrerelease: false
        )

        do {
            _ = try AppUpdatePolicy.availableUpdate(currentVersion: "1.0.0", release: release)
            expect(false, "URL tierce rejetée")
        } catch AppUpdateValidationError.invalidRelease {
            expect(true, "URL tierce rejetée")
        } catch {
            expect(false, "erreur attendue pour une URL tierce")
        }

        let mismatchedRelease = GitHubRelease(
            tagName: "v9.0.0",
            htmlURL: URL(string: "https://github.com/growthcroissance/capote/releases/tag/v8.0.0")!,
            isDraft: false,
            isPrerelease: false
        )

        do {
            _ = try AppUpdatePolicy.availableUpdate(currentVersion: "1.0.0", release: mismatchedRelease)
            expect(false, "page d’un autre tag rejetée")
        } catch AppUpdateValidationError.invalidRelease {
            expect(true, "page d’un autre tag rejetée")
        } catch {
            expect(false, "erreur attendue pour un tag incohérent")
        }
    }

    private static func testSessionRecoveryPolicy() {
        let expectedURL = URL(fileURLWithPath: "/private/tmp/capote-session.cancel")
        let otherURL = URL(fileURLWithPath: "/private/tmp/other-session.cancel")

        expect(
            SessionRecoveryPolicy.shouldRestoreDirectly(
                isSleepDisabled: true,
                currentCancellationURL: expectedURL,
                expectedCancellationURL: expectedURL
            ),
            "restauration de secours d’une session bloquée"
        )
        expect(
            !SessionRecoveryPolicy.shouldRestoreDirectly(
                isSleepDisabled: false,
                currentCancellationURL: expectedURL,
                expectedCancellationURL: expectedURL
            ),
            "absence de restauration si la veille est déjà rétablie"
        )
        expect(
            !SessionRecoveryPolicy.shouldRestoreDirectly(
                isSleepDisabled: true,
                currentCancellationURL: otherURL,
                expectedCancellationURL: expectedURL
            ),
            "absence de restauration pour une autre session"
        )
    }

    private static func testLaunchAtLoginController() {
        let service = ManualLaunchAtLoginService(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        controller.setRegistered(true)
        expect(controller.status == .enabled, "activation du lancement automatique")

        service.status = .requiresApproval
        controller.refresh()
        expect(controller.isRegistered, "actualisation d’une autorisation externe requise")

        controller.setRegistered(false)
        expect(controller.status == .notRegistered, "désactivation du lancement automatique")
    }

    private static func testMissingLaunchAtLoginRecord() {
        expect(
            LaunchAtLoginStatusMapper.map(.notFound) == .notRegistered,
            "état initial sans enregistrement interprété comme désactivé"
        )
    }

    private static func testRemotePairingAndEncryption() {
        do {
            let pairingCode = try RemoteControlCrypto.makePairingCode()
            let serviceID = UUID()
            let deviceID = UUID()
            let nonce = try RemoteControlCrypto.randomData(count: 16)
            let proof = try RemoteControlCrypto.pairingProof(
                pairingCode: pairingCode,
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
            try RemoteControlCrypto.verifyPairRequest(request, pairingCode: pairingCode)

            let deviceKey = try RemoteControlCrypto.randomData(count: 32)
            let wrapped = try RemoteControlCrypto.sealDeviceKey(
                deviceKey,
                pairingCode: pairingCode,
                nonce: nonce
            )
            let unwrapped = try RemoteControlCrypto.openDeviceKey(
                wrapped,
                pairingCode: pairingCode,
                nonce: nonce
            )
            expect(unwrapped == deviceKey, "jumelage distant chiffré")
        } catch {
            expect(false, "jumelage distant chiffré")
        }
    }

    private static func testRemoteCommandValidation() {
        expect(
            RemoteCommandAction.allCases.map(\.rawValue) == ["status", "restoreSleep"],
            "protocole distant limité à l’état et à l’arrêt"
        )

        let now = Date()
        let validator = RemoteCommandValidator()
        let command = RemoteCommand(issuedAt: now, action: .status)

        do {
            try validator.validate(command, now: now)
            do {
                try validator.validate(command, now: now)
                expect(false, "rejeu distant rejeté")
            } catch RemoteCommandValidationError.replayed {
                expect(true, "rejeu distant rejeté")
            } catch {
                expect(false, "rejeu distant rejeté")
            }

        } catch {
            expect(false, "validation d’une commande distante")
        }
    }

    private static func testRemoteFrameCodec() {
        do {
            let key = try RemoteControlCrypto.randomData(count: 32)
            let command = RemoteCommand(action: .restoreSleep)
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
            expect(
                decodedCommand.identifier == command.identifier
                    && decodedCommand.action == command.action,
                "trame distante chiffrée"
            )
        } catch {
            fputs("Erreur de trame distante : \(error)\n", stderr)
            expect(false, "trame distante chiffrée")
        }
    }

    private static func testRemoteTamperRejection() {
        do {
            let key = try RemoteControlCrypto.randomData(count: 32)
            var sealed = try RemoteControlCrypto.seal(RemoteCommand(action: .status), using: key)
            sealed[sealed.startIndex] ^= 0x01
            do {
                let _: RemoteCommand = try RemoteControlCrypto.open(
                    RemoteCommand.self,
                    from: sealed,
                    using: key
                )
                expect(false, "altération chiffrée rejetée")
            } catch RemoteCryptoError.invalidSealedPayload {
                expect(true, "altération chiffrée rejetée")
            }
        } catch {
            expect(false, "altération chiffrée rejetée")
        }
    }

    private static func testRemoteExpiredCommandRejection() {
        let issuedAt = Date().addingTimeInterval(-60)
        let command = RemoteCommand(issuedAt: issuedAt, lifetime: 30, action: .status)
        do {
            try RemoteCommandValidator().validate(command)
            expect(false, "commande distante expirée rejetée")
        } catch RemoteCommandValidationError.expired {
            expect(true, "commande distante expirée rejetée")
        } catch {
            expect(false, "commande distante expirée rejetée")
        }
    }

    private static func testTailscaleAddressValidation() {
        expect(RemoteDirectAccess.port == 51_684, "port distant stable")
        expect(
            RemoteDirectAccess.normalizedTailscaleHost(" MAC.PERSO.TS.NET. ") == "mac.perso.ts.net",
            "nom MagicDNS Tailscale normalisé"
        )
        expect(
            RemoteDirectAccess.normalizedTailscaleHost("100.64.0.1") == "100.64.0.1",
            "adresse IPv4 Tailscale acceptée"
        )
        expect(
            RemoteDirectAccess.normalizedTailscaleHost("[fd7a:115c:a1e0::1]") == "fd7a:115c:a1e0::1",
            "adresse IPv6 Tailscale acceptée"
        )
        expect(
            RemoteDirectAccess.normalizedTailscaleHost("example.com") == nil
                && RemoteDirectAccess.normalizedTailscaleHost("192.168.1.10") == nil
                && RemoteDirectAccess.normalizedTailscaleHost("100.128.0.1") == nil,
            "adresse hors Tailscale rejetée"
        )
    }

    private static func testTailscaleRoutePreference() {
        expect(
            RemoteDirectAccess.preferredRoutes(
                hasTailscaleHost: true,
                hasLocalEndpoint: true
            ) == [.localNetwork, .tailscale],
            "réseau local prioritaire lorsqu’il est disponible"
        )
        expect(
            RemoteDirectAccess.preferredRoutes(
                hasTailscaleHost: false,
                hasLocalEndpoint: true
            ) == [.localNetwork],
            "réseau local seul sans Tailscale"
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Échec : \(name)\n", stderr)
            exit(1)
        }
    }
}

@MainActor
private final class ManualLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }
}
