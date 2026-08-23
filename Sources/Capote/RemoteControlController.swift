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
    }

    private let keyStore = RemoteDeviceKeyStore()
    private var agent: MacRemoteAgent?

    private init() {
        pairedDevices = keyStore.devices()
    }

    func setEnabled(_ enabled: Bool) {
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
            statusText = "Saisissez ce code dans Capote pour iPhone. Il ne fonctionne qu’une fois."
        } catch {
            statusText = "Impossible de créer le code de jumelage."
        }
    }

    func cancelPairing() {
        pairingCode = nil
        statusText = "Contrôle iPhone disponible sur le réseau local."
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
            statusText = "Impossible d’écouter sur le réseau local : \(error.localizedDescription)"
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
        return RemoteMacStatus(
            isSleepDisabled: controller.isSleepDisabled,
            canRestoreActiveSession: controller.hasCancellableSession,
            activeSessionDescription: controller.activeSessionDescription,
            sessionEndDate: controller.sessionEndDate
        )
    }
}
