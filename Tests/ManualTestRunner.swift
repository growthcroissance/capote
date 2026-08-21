import Foundation

@main
struct ManualTestRunner {
    static func main() {
        testEnabledState()
        testDisabledState()
        testMissingState()
        testDurationArguments()
        testDownloadArguments()
        testThermalTerminationReasons()
        testCommandEscaping()
        testSessionRecoveryPolicy()
        print("8 tests réussis")
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Échec : \(name)\n", stderr)
            exit(1)
        }
    }
}
