import Foundation
#if SWIFT_PACKAGE
import CapoteRemoteCore
#endif

@MainActor
final class RemoteControlController: ObservableObject {
    static let shared = RemoteControlController()

    @Published private(set) var isEnabled = false
    @Published private(set) var pairingCode: String?
    @Published private(set) var statusText = "Contrôle iPhone désactivé"
    @Published private(set) var pairedDevices: [PairedRemoteDevice] = []

    private enum DefaultsKey {
        static let serviceIdentifier = "remoteControl.serviceIdentifier"
        static let isEnabled = "remoteControl.isEnabled"
    }

    private let keyStore = RemoteDeviceKeyStore()
    private var agent: MacRemoteAgent?

    private init() {
        pairedDevices = keyStore.devices()
        let persisted = UserDefaults.standard.object(forKey: DefaultsKey.isEnabled) as? Bool
        let shouldStart = persisted ?? !pairedDevices.isEmpty
        if shouldStart {
            UserDefaults.standard.set(true, forKey: DefaultsKey.isEnabled)
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.isEnabled)
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func startPairing() {
        guard isEnabled, let agent else { return }
        do {
            pairingCode = try agent.beginPairing()
            statusText = "Scannez le QR code dans Capote pour iPhone, ou saisissez le code. Il ne fonctionne qu’une fois."
        } catch {
            statusText = "Impossible de créer le code de jumelage."
        }
    }

    func cancelPairing() {
        agent?.cancelPairing()
        pairingCode = nil
        statusText = "Contrôle iPhone disponible localement et via Tailscale."
    }

    func remove(_ device: PairedRemoteDevice) {
        keyStore.remove(deviceIdentifier: device.id)
        pairedDevices = keyStore.devices()
        statusText = "\(device.name) a été révoqué."
    }

    private func start() {
        guard !isEnabled else { return }
        let agent = MacRemoteAgent(
            serviceIdentifier: serviceIdentifier(),
            keyStore: keyStore,
            commandHandler: { command, completion in
                Task { @MainActor in
                    Self.execute(command, completion: completion)
                }
            },
            eventHandler: { event in
                Task { @MainActor in
                    Self.shared.handle(event)
                }
            }
        )
        do {
            try agent.start()
            self.agent = agent
            isEnabled = true
            statusText = "Démarrage du contrôle iPhone…"
        } catch {
            statusText = "Impossible d’ouvrir le contrôle iPhone : \(error.localizedDescription)"
        }
    }

    private func stop() {
        agent?.stop()
        agent = nil
        pairingCode = nil
        isEnabled = false
        statusText = "Contrôle iPhone désactivé"
    }

    private func handle(_ event: String) {
        statusText = event
        pairedDevices = keyStore.devices()
        if event.contains("jumelé") {
            pairingCode = nil
        }
    }

    private func serviceIdentifier() -> UUID {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: DefaultsKey.serviceIdentifier), let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: DefaultsKey.serviceIdentifier)
        return identifier
    }

    private static func execute(
        _ command: RemoteCommand,
        completion: @escaping @Sendable (RemoteExecutionResult) -> Void
    ) {
        let sleepController = SleepControlController.shared

        switch command.action {
        case .status:
            sleepController.refresh()
            completion(RemoteExecutionResult(
                accepted: true,
                message: "État du Mac actualisé.",
                status: currentStatus()
            ))
        case .restoreSleep:
            if sleepController.hasCancellableSession {
                sleepController.disableSleepPrevention()
                completion(RemoteExecutionResult(
                    accepted: true,
                    message: "Restauration de la veille demandée.",
                    status: currentStatus()
                ))
                return
            }
            completion(RemoteExecutionResult(
                accepted: false,
                message: "Aucune session Capote contrôlable n’est active sur ce Mac.",
                status: currentStatus()
            ))
        }
    }

    private static func currentStatus() -> RemoteMacStatus {
        let controller = SleepControlController.shared
        let powerStatus = MacPowerStatusProvider.current()
        return RemoteMacStatus(
            isSleepDisabled: controller.isSleepDisabled,
            canRestoreActiveSession: controller.hasCancellableSession,
            activeSessionDescription: controller.activeSessionDescription,
            sessionEndDate: controller.sessionEndDate,
            thermalState: currentThermalState(),
            tailscaleHost: TailscaleAddressResolver.currentIPv4(),
            batteryLevelPercent: powerStatus?.batteryLevelPercent,
            powerSource: powerStatus?.powerSource
        )
    }

    private static func currentThermalState() -> RemoteThermalState {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .nominal
        case .fair: return .fair
        case .serious: return .serious
        case .critical: return .critical
        @unknown default: return .unknown
        }
    }
}

private enum TailscaleAddressResolver {
    private static let executablePaths = [
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/usr/local/bin/tailscale"
    ]

    static func currentIPv4() -> String? {
        for path in executablePaths where FileManager.default.isExecutableFile(atPath: path) {
            if let address = runCLI(at: path) {
                return address
            }
        }
        return nil
    }

    private static func runCLI(at path: String) -> String? {
        let process = Process()
        let output = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["ip", "-4"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["TAILSCALE_BE_CLI": "1"],
            uniquingKeysWith: { _, override in override }
        )
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in completion.signal() }

        do {
            try process.run()
        } catch {
            return nil
        }

        guard completion.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        return RemoteDirectAccess.firstTailscaleIPv4(in: value)
    }
}
