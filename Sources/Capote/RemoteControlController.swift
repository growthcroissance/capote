import AppKit
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
    @Published private(set) var privilegedStatus = PrivilegedRemoteClient.shared.status

    private enum DefaultsKey {
        static let serviceIdentifier = "remoteControl.serviceIdentifier"
    }

    private let keyStore = RemoteDeviceKeyStore()
    private var agent: MacRemoteAgent?

    private init() {
        pairedDevices = keyStore.devices()
    }

    var canRegisterPrivilegedService: Bool {
        PrivilegedRemoteClient.shared.hasStableSignature
            && privilegedStatus == .notRegistered
    }

    var privilegedStatusText: String {
        switch privilegedStatus {
        case .unavailableSignature:
            return "Le démarrage distant nécessite une signature Developer ID stable."
        case .notRegistered:
            return "Helper privilégié non installé."
        case .requiresApproval:
            return "Helper à approuver dans Réglages Système."
        case .enabled:
            return "Helper privilégié prêt."
        case .unknown:
            return "État du helper privilégié inconnu."
        }
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

    func refreshPrivilegedStatus() {
        privilegedStatus = PrivilegedRemoteClient.shared.status
    }

    func registerPrivilegedService() {
        do {
            try PrivilegedRemoteClient.shared.register()
            refreshPrivilegedStatus()
        } catch {
            statusText = "Impossible d’enregistrer le helper privilégié."
        }
    }

    func openPrivilegedApprovalSettings() {
        PrivilegedRemoteClient.shared.openApprovalSettings()
    }

    func unregisterPrivilegedService() {
        let client = PrivilegedRemoteClient.shared
        client.perform(PrivilegedRemoteRequest(action: .restoreSleep)) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                guard case .success(let response) = result, response.accepted else {
                    self.statusText = "Le helper n’a pas confirmé la restauration de la veille ; retrait annulé."
                    return
                }
                do {
                    try client.unregister()
                    self.refreshPrivilegedStatus()
                    self.statusText = "Helper privilégié retiré après restauration de la veille."
                } catch {
                    self.statusText = "Impossible de retirer le helper privilégié."
                }
            }
        }
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
            eventHandler: { [weak self] event in
                Task { @MainActor in
                    self?.statusText = event
                    self?.pairedDevices = self?.keyStore.devices() ?? []
                    if event.contains("jumelé") {
                        self?.pairingCode = nil
                    }
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
        let privilegedClient = PrivilegedRemoteClient.shared

        if privilegedClient.status == .enabled {
            let action: PrivilegedRemoteAction
            switch command.action {
            case .status: action = .status
            case .startDuration: action = .startDuration
            case .restoreSleep: action = .restoreSleep
            }
            privilegedClient.perform(
                PrivilegedRemoteRequest(
                    identifier: command.identifier,
                    action: action,
                    durationSeconds: command.durationSeconds
                )
            ) { result in
                Task { @MainActor in
                    switch result {
                    case .success(let response):
                        sleepController.refresh()
                        completion(
                            RemoteExecutionResult(
                                accepted: response.accepted,
                                message: response.message,
                                status: RemoteMacStatus(
                                    isSleepDisabled: response.isSleepDisabled,
                                    isRemoteControlReady: true,
                                    activeSessionDescription: response.sessionEndDate == nil
                                        ? sleepController.activeSessionDescription
                                        : "Session démarrée depuis l’iPhone",
                                    sessionEndDate: response.sessionEndDate,
                                    thermalSafetyTriggered: response.thermalSafetyTriggered
                                )
                            )
                        )
                    case .failure:
                        completion(
                            RemoteExecutionResult(
                                accepted: false,
                                message: "Le helper privilégié n’a pas répondu.",
                                status: currentStatus(remoteReady: false)
                            )
                        )
                    }
                }
            }
            return
        }

        switch command.action {
        case .status:
            sleepController.refresh()
            completion(RemoteExecutionResult(
                accepted: true,
                message: "État du Mac actualisé.",
                status: currentStatus(remoteReady: false)
            ))
        case .restoreSleep:
            if sleepController.hasCancellableSession {
                sleepController.disableSleepPrevention()
                completion(RemoteExecutionResult(
                    accepted: true,
                    message: "Restauration de la veille demandée.",
                    status: currentStatus(remoteReady: false)
                ))
                return
            }
            completion(RemoteExecutionResult(
                accepted: false,
                message: "Le helper privilégié permanent n’est pas encore approuvé sur ce Mac.",
                status: currentStatus(remoteReady: false)
            ))
        case .startDuration:
            completion(RemoteExecutionResult(
                accepted: false,
                message: "Activez d’abord le helper privilégié signé sur le Mac.",
                status: currentStatus(remoteReady: false)
            ))
        }
    }

    private static func currentStatus(remoteReady: Bool) -> RemoteMacStatus {
        let controller = SleepControlController.shared
        return RemoteMacStatus(
            isSleepDisabled: controller.isSleepDisabled,
            isRemoteControlReady: remoteReady,
            activeSessionDescription: controller.activeSessionDescription,
            sessionEndDate: controller.sessionEndDate
        )
    }
}
