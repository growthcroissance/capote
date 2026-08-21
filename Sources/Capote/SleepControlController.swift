import AppKit
import Foundation
import UserNotifications

struct RunningApplicationOption: Identifiable, Equatable {
    let pid: pid_t
    let name: String

    var id: Int32 { pid }
}

enum SessionRequest: Equatable {
    case indefinite
    case duration(TimeInterval)
    case process(pid_t)
    case download(path: String, stableSeconds: TimeInterval)

    func helperArguments(cancelURL: URL, resultURL: URL) -> [String] {
        var arguments = [
            "--user-uid",
            String(getuid()),
            "--cancel-base64",
            Data(cancelURL.path.utf8).base64EncodedString(),
            "--result-base64",
            Data(resultURL.path.utf8).base64EncodedString()
        ]

        switch self {
        case .indefinite:
            arguments += ["--mode", "indefinite"]
        case .duration(let seconds):
            arguments += ["--mode", "duration", "--seconds", String(seconds)]
        case .process(let pid):
            arguments += ["--mode", "process", "--pid", String(pid)]
        case .download(let path, let stableSeconds):
            arguments += [
                "--mode", "download",
                "--path-base64", Data(path.utf8).base64EncodedString(),
                "--stable-seconds", String(stableSeconds)
            ]
        }

        return arguments
    }
}

enum SessionTerminationReason: Equatable {
    case thermalSerious
    case thermalCritical

    static func parse(_ data: Data?) -> SessionTerminationReason? {
        guard let data,
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        switch value {
        case "thermal-serious": return .thermalSerious
        case "thermal-critical": return .thermalCritical
        default: return nil
        }
    }

    var userMessage: String {
        switch self {
        case .thermalSerious:
            return "Capote a rétabli la veille car macOS signale une température élevée."
        case .thermalCritical:
            return "Capote a rétabli la veille car macOS signale une température critique."
        }
    }
}

private final class ThermalNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ThermalNotificationService()

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func deliver(_ reason: SessionTerminationReason) {
        let content = UNMutableNotificationContent()
        content.title = "Sécurité thermique Capote"
        content.body = reason.userMessage
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "thermal-safety-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

enum SessionCommandEscaping {
    static func appleScriptLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}

@MainActor
final class SleepControlController: ObservableObject {
    static let shared = SleepControlController()

    private enum DefaultsKey {
        static let cancellationPath = "activeSession.cancellationPath"
        static let description = "activeSession.description"
        static let endDate = "activeSession.endDate"
        static let resultPath = "activeSession.resultPath"
    }

    @Published private(set) var isSleepDisabled: Bool?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var activeSessionDescription: String?
    @Published private(set) var sessionEndDate: Date?
    @Published private(set) var now = Date()
    @Published private(set) var runningApplications: [RunningApplicationOption] = []

    private var sessionProcess: Process?
    private var cancellationURL: URL?
    private var resultURL: URL?
    private var pollingTimer: Timer?
    private var quitAfterSession = false
    private var lastSessionExitStatus: Int32?

    var statusText: String {
        if isBusy {
            return "Autorisation ou modification en cours…"
        }

        switch isSleepDisabled {
        case true:
            return "Veille désactivée, y compris capot fermé"
        case false:
            return "Démarrer une nouvelle session"
        case nil:
            return "État de veille inconnu"
        }
    }

    var remainingText: String? {
        guard let sessionEndDate else { return nil }
        let seconds = max(0, Int(ceil(sessionEndDate.timeIntervalSince(now))))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60

        if hours > 0 {
            return String(format: "Fin dans %d h %02d min", hours, minutes)
        }

        return String(format: "Fin dans %d min %02d s", minutes, remainder)
    }

    private init() {
        ThermalNotificationService.shared.configure()
        loadPersistedSession()
        refresh()
        refreshRunningApplications()

        if cancellationURL != nil, isSleepDisabled == true {
            startPolling()
        }
    }

    func menuDidOpen() {
        refresh()
        refreshRunningApplications()
        now = Date()
    }

    func refresh() {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "live"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(decoding: data, as: UTF8.self)

            guard process.terminationStatus == 0,
                  let state = SleepDisabledState.parse(pmsetOutput: text) else {
                isSleepDisabled = nil
                errorMessage = "Impossible de lire l’état SleepDisabled."
                return
            }

            isSleepDisabled = state
            errorMessage = nil

            if state, sessionProcess != nil {
                isBusy = false
            }

            if !state, sessionProcess == nil {
                let terminationReason = consumeSessionTerminationReason()
                clearPersistedSession()
                isBusy = false

                if let terminationReason {
                    errorMessage = terminationReason.userMessage
                    ThermalNotificationService.shared.deliver(terminationReason)
                } else if let lastSessionExitStatus, lastSessionExitStatus != 0 {
                    errorMessage = "Session annulée ou refusée par macOS."
                }

                lastSessionExitStatus = nil

                if quitAfterSession {
                    quitAfterSession = false
                    NSApp.terminate(nil)
                }
            }
        } catch {
            isSleepDisabled = nil
            errorMessage = "Impossible de lancer pmset : \(error.localizedDescription)"
        }
    }

    func refreshRunningApplications() {
        let ownPID = ProcessInfo.processInfo.processIdentifier

        runningApplications = NSWorkspace.shared.runningApplications
            .compactMap { application -> RunningApplicationOption? in
                guard application.processIdentifier != ownPID,
                      application.activationPolicy != .prohibited,
                      let name = application.localizedName,
                      !name.isEmpty else {
                    return nil
                }

                return RunningApplicationOption(pid: application.processIdentifier, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func startIndefinitely() {
        startSession(.indefinite, description: "Session sans limite", endDate: nil)
    }

    func startDuration(seconds: TimeInterval, description: String) {
        guard seconds > 0 else { return }
        startSession(
            .duration(seconds),
            description: description,
            endDate: Date().addingTimeInterval(seconds)
        )
    }

    func chooseEndDate() {
        let picker = NSDatePicker(frame: NSRect(x: 0, y: 0, width: 300, height: 28))
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.minDate = Date().addingTimeInterval(60)
        picker.dateValue = Date().addingTimeInterval(3_600)

        let alert = NSAlert()
        alert.messageText = "Empêcher la veille jusqu’à…"
        alert.informativeText = "Choisissez la date et l’heure de restauration automatique."
        alert.accessoryView = picker
        alert.addButton(withTitle: "Continuer")
        alert.addButton(withTitle: "Annuler")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let seconds = picker.dateValue.timeIntervalSinceNow
        guard seconds > 1 else {
            errorMessage = "Choisissez une heure de fin dans le futur."
            return
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        startSession(
            .duration(seconds),
            description: "Jusqu’au \(formatter.string(from: picker.dateValue))",
            endDate: picker.dateValue
        )
    }

    func startWhileRunning(_ application: RunningApplicationOption) {
        startSession(
            .process(application.pid),
            description: "Tant que \(application.name) est ouvert",
            endDate: nil
        )
    }

    func chooseDownload() {
        let panel = NSOpenPanel()
        panel.title = "Choisir le téléchargement à surveiller"
        panel.prompt = "Surveiller"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let delayPicker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        [5, 10, 30, 60].forEach { delayPicker.addItem(withTitle: "\($0) secondes") }
        delayPicker.selectItem(withTitle: "10 secondes")

        let alert = NSAlert()
        alert.messageText = "Délai de fin du téléchargement"
        alert.informativeText = "La veille sera rétablie si le fichier ne change plus pendant ce délai."
        alert.accessoryView = delayPicker
        alert.addButton(withTitle: "Continuer")
        alert.addButton(withTitle: "Annuler")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let delays: [TimeInterval] = [5, 10, 30, 60]
        let selectedDelay = delays[max(0, delayPicker.indexOfSelectedItem)]
        startSession(
            .download(path: url.path, stableSeconds: selectedDelay),
            description: "Pendant le téléchargement de \(url.lastPathComponent)",
            endDate: nil
        )
    }

    func disableSleepPrevention(quitAfter: Bool = false) {
        quitAfterSession = quitAfter

        if let cancellationURL {
            isBusy = true

            do {
                try Data().write(to: cancellationURL, options: .atomic)
                errorMessage = nil
                startPolling()
            } catch {
                isBusy = false
                errorMessage = "Impossible d’arrêter la session : \(error.localizedDescription)"
            }
            return
        }

        applySleepDisabled(false, quitAfter: quitAfter)
    }

    private func startSession(_ request: SessionRequest, description: String, endDate: Date?) {
        guard !isBusy, sessionProcess == nil else { return }
        guard confirmStart(description: description) else { return }

        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/CapoteSession")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            errorMessage = "Le helper CapoteSession est absent du bundle."
            return
        }

        let cancelURL = URL(fileURLWithPath: "/private/tmp/fr.benjaminfarrudja.capote-\(getuid())-\(UUID().uuidString).cancel")
        let resultURL = URL(fileURLWithPath: cancelURL.path.replacingOccurrences(of: ".cancel", with: ".result"))

        guard FileManager.default.createFile(atPath: resultURL.path, contents: Data()) else {
            errorMessage = "Impossible de préparer le suivi de la session."
            return
        }

        let arguments = request.helperArguments(cancelURL: cancelURL, resultURL: resultURL)
        let command = ([SessionCommandEscaping.shellQuote(helperURL.path)] + arguments).joined(separator: " ")
        let script = "do shell script \"\(SessionCommandEscaping.appleScriptLiteral(command))\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard let self, let process, self.sessionProcess === process else { return }
                self.sessionDidEnd(status: process.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: resultURL)
            errorMessage = "Impossible de demander l’autorisation : \(error.localizedDescription)"
            return
        }

        sessionProcess = process
        cancellationURL = cancelURL
        self.resultURL = resultURL
        activeSessionDescription = description
        sessionEndDate = endDate
        now = Date()
        isBusy = true
        errorMessage = nil
        persistSession(cancelURL: cancelURL, resultURL: resultURL, description: description, endDate: endDate)
        startPolling()
    }

    private func confirmStart(description: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Démarrer cette session Capote ?"
        alert.informativeText = "\(description). Le Mac peut continuer à chauffer capot fermé. Ne l’utilisez jamais dans un sac ou sans ventilation. Une seule autorisation administrateur sera demandée."
        alert.addButton(withTitle: "Démarrer")
        alert.addButton(withTitle: "Annuler")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.now = Date()
                self.refresh()
            }
        }
    }

    private func sessionDidEnd(status: Int32) {
        pollingTimer?.invalidate()
        pollingTimer = nil
        sessionProcess = nil
        lastSessionExitStatus = status
        isBusy = false
        refresh()

        if quitAfterSession, isSleepDisabled == false {
            quitAfterSession = false
            NSApp.terminate(nil)
        }
    }

    private func loadPersistedSession() {
        let defaults = UserDefaults.standard

        if let path = defaults.string(forKey: DefaultsKey.cancellationPath) {
            cancellationURL = URL(fileURLWithPath: path)
        }

        if let path = defaults.string(forKey: DefaultsKey.resultPath) {
            resultURL = URL(fileURLWithPath: path)
        }

        activeSessionDescription = defaults.string(forKey: DefaultsKey.description)
        sessionEndDate = defaults.object(forKey: DefaultsKey.endDate) as? Date
    }

    private func persistSession(cancelURL: URL, resultURL: URL, description: String, endDate: Date?) {
        let defaults = UserDefaults.standard
        defaults.set(cancelURL.path, forKey: DefaultsKey.cancellationPath)
        defaults.set(resultURL.path, forKey: DefaultsKey.resultPath)
        defaults.set(description, forKey: DefaultsKey.description)

        if let endDate {
            defaults.set(endDate, forKey: DefaultsKey.endDate)
        } else {
            defaults.removeObject(forKey: DefaultsKey.endDate)
        }
    }

    private func clearPersistedSession() {
        if let cancellationURL {
            try? FileManager.default.removeItem(at: cancellationURL)
        }

        if let resultURL {
            try? FileManager.default.removeItem(at: resultURL)
        }

        cancellationURL = nil
        resultURL = nil
        activeSessionDescription = nil
        sessionEndDate = nil

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: DefaultsKey.cancellationPath)
        defaults.removeObject(forKey: DefaultsKey.resultPath)
        defaults.removeObject(forKey: DefaultsKey.description)
        defaults.removeObject(forKey: DefaultsKey.endDate)
    }

    private func consumeSessionTerminationReason() -> SessionTerminationReason? {
        guard let resultURL else { return nil }
        return SessionTerminationReason.parse(try? Data(contentsOf: resultURL))
    }

    private func applySleepDisabled(_ disabled: Bool, quitAfter: Bool) {
        guard !isBusy else { return }

        isBusy = true
        errorMessage = nil

        let value = disabled ? "1" : "0"
        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false

                    guard process.terminationStatus == 0 else {
                        self.errorMessage = "Modification annulée ou refusée par macOS."
                        self.refresh()
                        return
                    }

                    self.refresh()

                    if quitAfter, self.isSleepDisabled == false {
                        NSApp.terminate(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.isBusy = false
                    self.errorMessage = "Impossible de demander l’autorisation : \(error.localizedDescription)"
                    self.refresh()
                }
            }
        }
    }

}

enum SleepDisabledState {
    static func parse(pmsetOutput: String) -> Bool? {
        for line in pmsetOutput.split(whereSeparator: \Character.isNewline) {
            let fields = line.split(whereSeparator: \Character.isWhitespace)

            guard fields.count >= 2,
                  fields[0].caseInsensitiveCompare("SleepDisabled") == .orderedSame else {
                continue
            }

            switch fields[1] {
            case "0": return false
            case "1": return true
            default: return nil
            }
        }

        return nil
    }
}
