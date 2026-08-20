import Foundation

@main
struct ManualTestRunner {
    static func main() {
        testEnabledState()
        testDisabledState()
        testMissingState()
        testDurationArguments()
        testDownloadArguments()
        testCommandEscaping()
        print("6 tests réussis")
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
        let arguments = SessionRequest.duration(300).helperArguments(cancelURL: cancelURL)

        expect(arguments.contains("duration"), "arguments du mode durée")
        expect(arguments.contains("300.0"), "durée transmise au helper")
    }

    private static func testDownloadArguments() {
        let cancelURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-test.cancel")
        let arguments = SessionRequest.download(
            path: "/tmp/fichier avec espaces.download",
            stableSeconds: 10
        ).helperArguments(cancelURL: cancelURL)

        expect(arguments.contains("download"), "arguments du mode téléchargement")
        expect(!arguments.contains("/tmp/fichier avec espaces.download"), "chemin encodé en base64")
    }

    private static func testCommandEscaping() {
        let shellQuoted = SessionCommandEscaping.shellQuote("/tmp/L'app Capote")
        let appleScriptQuoted = SessionCommandEscaping.appleScriptLiteral("commande \"test\"")

        expect(shellQuoted == "'/tmp/L'\"'\"'app Capote'", "échappement shell du chemin")
        expect(appleScriptQuoted == "commande \\\"test\\\"", "échappement de la chaîne AppleScript")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else {
            fputs("Échec : \(name)\n", stderr)
            exit(1)
        }
    }
}
