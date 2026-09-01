import Foundation
import Network
import UIKit
import CapoteRemoteCore

struct DiscoveredMac: Identifiable, Equatable {
    let id: UUID
    let name: String
    let endpoint: NWEndpoint

    static func == (lhs: DiscoveredMac, rhs: DiscoveredMac) -> Bool {
        lhs.id == rhs.id && lhs.endpoint == rhs.endpoint
    }
}

struct PairedMac: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var tailscaleHost: String?
}

protocol CompanionTransport {
    var connectionLabel: String { get }

    func send(
        _ wire: RemoteWireMessage,
        completion: @escaping (Result<CompanionTransportResponse, Error>) -> Void
    )
}

struct CompanionTransportResponse {
    let wire: RemoteWireMessage
    let connectionLabel: String
}

private enum RemoteStatusPresentation: Equatable {
    case unknown
    case cached
    case current
    case unavailable
}

private struct CachedRemoteStatus: Codable {
    let macIdentifier: UUID
    let status: RemoteMacStatus
    let updatedAt: Date
}

@MainActor
final class CompanionModel: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var pairedMacs: [PairedMac] = []
    @Published private(set) var selectedMac: PairedMac?
    @Published private(set) var status: RemoteMacStatus?
    @Published private(set) var message: String?
    @Published private(set) var isConnecting = false
    @Published private(set) var successfulConnectionLabel: String?
    @Published private(set) var lastStatusUpdate: Date?
    @Published private var statusPresentation: RemoteStatusPresentation = .unknown

    private let browserQueue = DispatchQueue(label: "fr.benjaminfarrudja.capote.companion-browser")
    private let keyStore = CompanionKeyStore()
    private var browser: NWBrowser?
    private var activeRequestIdentifier: UUID?
    private var shouldRefreshWhenSelectedMacIsDiscovered = false
    private var browserGeneration = UUID()
    private var isBrowserReady = false

    private enum DefaultsKey {
        static let deviceIdentifier = "companion.deviceIdentifier"
        static let pairedMacs = "companion.pairedMacs"
        static let selectedMac = "companion.selectedMac"
        static let cachedStatus = "companion.cachedStatus"
    }

    var connectionText: String {
        if isConnecting { return "Connexion…" }
        guard let selectedMac else { return "Aucun Mac" }
        if statusPresentation == .unavailable { return "Hors ligne" }
        if statusPresentation == .cached { return "Dernier état" }
        if let successfulConnectionLabel { return successfulConnectionLabel }
        if endpoint(for: selectedMac.id) != nil { return "Réseau local disponible" }
        if selectedMac.tailscaleHost != nil { return "Tailscale configuré" }
        return "Hors ligne"
    }

    var sleepStateText: String {
        if isConnecting { return "Actualisation…" }
        if statusPresentation == .unavailable { return "Indisponible" }
        switch status?.isSleepDisabled {
        case true: return "Désactivée"
        case false: return "Autorisée"
        case nil: return "Inconnu"
        }
    }

    init() {
        pairedMacs = Self.loadPairedMacs()
        let persistedIdentifier = UserDefaults.standard
            .string(forKey: DefaultsKey.selectedMac)
            .flatMap(UUID.init(uuidString:))
        let selectedIdentifier = CompanionSelectionPolicy.selectedIdentifier(
            persistedIdentifier: persistedIdentifier,
            availableIdentifiers: pairedMacs.map(\.id)
        )
        selectedMac = pairedMacs.first { $0.id == selectedIdentifier }
        restoreCachedStatus(for: selectedMac)
        persistSelectedMac()
    }

    func startBrowsing() {
        guard browser == nil else { return }
        let generation = UUID()
        browserGeneration = generation
        isBrowserReady = false
        let descriptor = NWBrowser.Descriptor.bonjour(type: CapoteRemoteProtocol.bonjourType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: CompanionNetworkParameters.localTCP())
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.compactMap { result -> (UUID, NWEndpoint)? in
                guard case .service(let name, _, _, _) = result.endpoint,
                      let identifier = UUID(uuidString: name) else { return nil }
                return (identifier, result.endpoint)
            }
            Task { @MainActor in
                guard let self, self.browserGeneration == generation else { return }
                self.discoveredMacs = endpoints.map { identifier, endpoint in
                    let displayName = self.pairedMacs.first(where: { $0.id == identifier })?.name
                        ?? "Mac avec Capote"
                    return DiscoveredMac(id: identifier, name: displayName, endpoint: endpoint)
                }.sorted { $0.name < $1.name }
                self.refreshWhenLocalBrowsingIsReady()
                if endpoints.isEmpty, self.successfulConnectionLabel == "Réseau local" {
                    self.successfulConnectionLabel = nil
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Task { @MainActor in
                    guard let self, self.browserGeneration == generation else { return }
                    self.isBrowserReady = true
                    self.refreshWhenLocalBrowsingIsReady()
                }
            case .waiting(let error), .failed(let error):
                Task { @MainActor in
                    guard let self, self.browserGeneration == generation else { return }
                    self.isBrowserReady = false
                    self.discoveredMacs = []
                    if self.successfulConnectionLabel == "Réseau local" {
                        self.successfulConnectionLabel = nil
                    }
                    self.message = "Recherche locale impossible : \(error.localizedDescription)"
                }
            case .cancelled:
                Task { @MainActor in
                    guard let self, self.browserGeneration == generation else { return }
                    self.isBrowserReady = false
                    self.discoveredMacs = []
                    if self.successfulConnectionLabel == "Réseau local" {
                        self.successfulConnectionLabel = nil
                    }
                }
            default:
                break
            }
        }
        self.browser = browser
        browser.start(queue: browserQueue)
    }

    func restartBrowsing() {
        browser?.browseResultsChangedHandler = nil
        browser?.stateUpdateHandler = nil
        browser?.cancel()
        browser = nil
        startBrowsing()
    }

    func handleActivation() {
        shouldRefreshWhenSelectedMacIsDiscovered = selectedMac != nil
        restartBrowsing()

        if selectedMac?.tailscaleHost != nil {
            shouldRefreshWhenSelectedMacIsDiscovered = false
            refresh()
        }
    }

    func refresh() {
        if selectedMac != nil { send(.status) }
    }

    private func refreshWhenLocalBrowsingIsReady() {
        guard shouldRefreshWhenSelectedMacIsDiscovered,
              isBrowserReady,
              let selectedIdentifier = selectedMac?.id,
              endpoint(for: selectedIdentifier) != nil else { return }
        shouldRefreshWhenSelectedMacIsDiscovered = false
        refresh()
    }

    func select(_ mac: PairedMac) {
        selectedMac = mac
        status = nil
        lastStatusUpdate = nil
        statusPresentation = .unknown
        successfulConnectionLabel = nil
        persistSelectedMac()
        restoreCachedStatus(for: mac)
        send(.status)
    }

    func pair(_ mac: DiscoveredMac, code: String, completion: @escaping (Bool) -> Void) {
        guard !isConnecting else { return }
        isConnecting = true
        message = nil
        let requestIdentifier = UUID()
        activeRequestIdentifier = requestIdentifier

        do {
            let nonce = try RemoteControlCrypto.randomData(count: 16)
            let deviceID = deviceIdentifier()
            let deviceName = UIDevice.current.name
            let request = PairRequest(
                serviceIdentifier: mac.id,
                deviceIdentifier: deviceID,
                deviceName: deviceName,
                nonce: nonce,
                proof: try RemoteControlCrypto.pairingProof(
                    pairingCode: code,
                    serviceIdentifier: mac.id,
                    deviceIdentifier: deviceID,
                    deviceName: deviceName,
                    nonce: nonce
                )
            )
            let wire = RemoteWireMessage(
                kind: .pairRequest,
                payload: try JSONEncoder.capoteRemote.encode(request)
            )
            SocketCompanionTransport(
                endpoint: mac.endpoint,
                connectionLabel: "réseau local",
                parameters: CompanionNetworkParameters.localTCP()
            ).send(wire) {
                [weak self] result in
                Task { @MainActor in
                    guard let self, self.activeRequestIdentifier == requestIdentifier else { return }
                    self.activeRequestIdentifier = nil
                    self.isConnecting = false
                    do {
                        let transportResponse = try result.get()
                        let responseWire = transportResponse.wire
                        if responseWire.kind == .error {
                            throw CompanionError.pairingRejected
                        }
                        guard responseWire.kind == .pairResponse else { throw CompanionError.unexpectedResponse }
                        let response = try JSONDecoder.capoteRemote.decode(PairResponse.self, from: responseWire.payload)
                        guard response.accepted,
                              response.serviceIdentifier == mac.id,
                              let wrappedKey = response.encryptedDeviceKey else {
                            throw CompanionError.pairingRejected
                        }
                        let key = try RemoteControlCrypto.openDeviceKey(wrappedKey, pairingCode: code, nonce: nonce)
                        try self.keyStore.save(key: key, for: mac.id)
                        let paired = PairedMac(id: mac.id, name: response.macName, tailscaleHost: nil)
                        self.pairedMacs.removeAll { $0.id == paired.id }
                        self.pairedMacs.append(paired)
                        self.savePairedMacs()
                        self.select(paired)
                        self.successfulConnectionLabel = "Réseau local"
                        self.message = response.message
                        completion(true)
                    } catch CompanionError.pairingRejected {
                        self.message = "Jumelage refusé. Créez un nouveau code sur le Mac, puis scannez son QR code."
                        completion(false)
                    } catch {
                        self.message = "Impossible de joindre le Mac pour le jumelage. Vérifiez que les deux appareils sont sur le même réseau local et que Capote est ouverte."
                        completion(false)
                    }
                }
            }
        } catch {
            activeRequestIdentifier = nil
            isConnecting = false
            message = "Code de jumelage invalide."
            completion(false)
        }
    }

    func send(_ action: RemoteCommandAction) {
        guard !isConnecting else { return }
        guard let mac = selectedMac,
              let key = keyStore.key(for: mac.id) else {
            status = nil
            lastStatusUpdate = nil
            statusPresentation = .unavailable
            successfulConnectionLabel = nil
            message = "La clé de jumelage de ce Mac n’est plus disponible."
            return
        }
        guard let transport = transport(for: mac) else {
            preserveCachedStatusAfterFailure(
                "Ce Mac n’est disponible ni localement ni via une adresse Tailscale configurée."
            )
            return
        }

        isConnecting = true
        message = nil
        let requestIdentifier = UUID()
        activeRequestIdentifier = requestIdentifier
        do {
            let command = RemoteCommand(action: action)
            let encrypted = EncryptedRemotePayload(
                deviceIdentifier: deviceIdentifier(),
                sealedPayload: try RemoteControlCrypto.seal(command, using: key)
            )
            let wire = RemoteWireMessage(
                kind: .command,
                payload: try JSONEncoder.capoteRemote.encode(encrypted)
            )
            transport.send(wire) { [weak self] result in
                Task { @MainActor in
                    guard let self, self.activeRequestIdentifier == requestIdentifier else { return }
                    self.activeRequestIdentifier = nil
                    self.isConnecting = false
                    do {
                        let transportResponse = try result.get()
                        let responseWire = transportResponse.wire
                        if responseWire.kind == .error {
                            throw CompanionError.remoteRejected
                        }
                        guard responseWire.kind == .response else { throw CompanionError.unexpectedResponse }
                        let encryptedResponse = try JSONDecoder.capoteRemote.decode(
                            EncryptedRemotePayload.self,
                            from: responseWire.payload
                        )
                        let response = try RemoteControlCrypto.open(
                            RemoteResponse.self,
                            from: encryptedResponse.sealedPayload,
                            using: key
                        )
                        guard response.commandIdentifier == command.identifier else {
                            throw CompanionError.unexpectedResponse
                        }
                        self.status = response.status
                        if let status = response.status {
                            let updatedAt = Date()
                            self.lastStatusUpdate = updatedAt
                            self.statusPresentation = .current
                            self.saveCachedStatus(status, for: mac.id, updatedAt: updatedAt)
                        } else {
                            self.lastStatusUpdate = nil
                            self.statusPresentation = .unknown
                        }
                        self.adoptTailscaleHost(response.status?.tailscaleHost, for: mac.id)
                        self.successfulConnectionLabel = transportResponse.connectionLabel
                        self.message = response.message
                    } catch CompanionError.remoteRejected {
                        self.status = nil
                        self.lastStatusUpdate = nil
                        self.statusPresentation = .unavailable
                        self.successfulConnectionLabel = nil
                        self.clearCachedStatus(for: mac.id)
                        self.message = "Le Mac a refusé cette clé de jumelage. Oubliez ce Mac sur l’iPhone, puis jumelez-le à nouveau avec un nouveau code."
                    } catch {
                        self.preserveCachedStatusAfterFailure(
                            "Réponse du Mac invalide ou connexion \(transport.connectionLabel) interrompue."
                        )
                    }
                }
            }
        } catch {
            activeRequestIdentifier = nil
            isConnecting = false
            preserveCachedStatusAfterFailure("Impossible de préparer la commande.")
        }
    }

    func remove(_ mac: PairedMac) {
        cancelConnection(message: nil)
        keyStore.remove(for: mac.id)
        pairedMacs.removeAll { $0.id == mac.id }
        savePairedMacs()
        clearCachedStatus(for: mac.id)
        if selectedMac?.id == mac.id {
            selectedMac = pairedMacs.first
            status = nil
            lastStatusUpdate = nil
            statusPresentation = .unknown
            successfulConnectionLabel = nil
            persistSelectedMac()
            restoreCachedStatus(for: selectedMac)
        }
        message = "Mac oublié sur cet iPhone. Jumelez-le à nouveau depuis le même réseau local."
    }

    func cancelConnection() {
        cancelConnection(message: "Connexion annulée.")
    }

    @discardableResult
    func saveTailscaleHost(_ value: String, for mac: PairedMac) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized: String?
        if trimmed.isEmpty {
            normalized = nil
        } else {
            guard let validHost = RemoteDirectAccess.normalizedTailscaleHost(trimmed) else {
                message = "Saisissez un nom MagicDNS complet en .ts.net ou une adresse IP Tailscale."
                return false
            }
            normalized = validHost
        }

        guard let index = pairedMacs.firstIndex(where: { $0.id == mac.id }) else {
            message = "Ce Mac n’est plus jumelé."
            return false
        }
        pairedMacs[index].tailscaleHost = normalized
        if selectedMac?.id == mac.id {
            selectedMac = pairedMacs[index]
        }
        successfulConnectionLabel = nil
        savePairedMacs()
        message = normalized == nil
            ? "Accès Tailscale supprimé."
            : "Accès Tailscale enregistré. Le jumelage chiffré existant reste utilisé."
        return true
    }

    private func endpoint(for identifier: UUID) -> NWEndpoint? {
        discoveredMacs.first { $0.id == identifier }?.endpoint
    }

    private func transport(for mac: PairedMac) -> CompanionTransport? {
        var transports: [SocketCompanionTransport] = []
        let localEndpoint = endpoint(for: mac.id)
        for route in RemoteDirectAccess.preferredRoutes(
            hasTailscaleHost: mac.tailscaleHost != nil,
            hasLocalEndpoint: localEndpoint != nil
        ) {
            switch route {
            case .tailscale:
                if let host = mac.tailscaleHost,
                   let port = NWEndpoint.Port(rawValue: RemoteDirectAccess.port) {
                    transports.append(SocketCompanionTransport(
                        endpoint: .hostPort(host: NWEndpoint.Host(host), port: port),
                        connectionLabel: "Tailscale",
                        parameters: .tcp
                    ))
                }
            case .localNetwork:
                if let localEndpoint {
                    transports.append(SocketCompanionTransport(
                        endpoint: localEndpoint,
                        connectionLabel: "Réseau local",
                        parameters: CompanionNetworkParameters.localTCP()
                    ))
                }
            }
        }
        guard !transports.isEmpty else { return nil }
        if transports.count == 1 { return transports[0] }
        return AdaptiveCompanionTransport(transports: transports)
    }

    private func deviceIdentifier() -> UUID {
        let defaults = UserDefaults.standard
        if let value = defaults.string(forKey: DefaultsKey.deviceIdentifier), let id = UUID(uuidString: value) {
            return id
        }
        let id = UUID()
        defaults.set(id.uuidString, forKey: DefaultsKey.deviceIdentifier)
        return id
    }

    private static func loadPairedMacs() -> [PairedMac] {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.pairedMacs) else { return [] }
        return (try? JSONDecoder.capoteRemote.decode([PairedMac].self, from: data)) ?? []
    }

    private static func loadCachedStatus() -> CachedRemoteStatus? {
        guard let data = UserDefaults.standard.data(forKey: DefaultsKey.cachedStatus) else { return nil }
        return try? JSONDecoder.capoteRemote.decode(CachedRemoteStatus.self, from: data)
    }

    private func restoreCachedStatus(for mac: PairedMac?) {
        guard let mac,
              let cached = Self.loadCachedStatus(),
              cached.macIdentifier == mac.id else { return }
        status = cached.status
        lastStatusUpdate = cached.updatedAt
        statusPresentation = .cached
    }

    private func saveCachedStatus(_ status: RemoteMacStatus, for identifier: UUID, updatedAt: Date) {
        let cached = CachedRemoteStatus(macIdentifier: identifier, status: status, updatedAt: updatedAt)
        UserDefaults.standard.set(try? JSONEncoder.capoteRemote.encode(cached), forKey: DefaultsKey.cachedStatus)
    }

    private func clearCachedStatus(for identifier: UUID) {
        guard Self.loadCachedStatus()?.macIdentifier == identifier else { return }
        UserDefaults.standard.removeObject(forKey: DefaultsKey.cachedStatus)
    }

    private func preserveCachedStatusAfterFailure(_ failureMessage: String) {
        successfulConnectionLabel = nil
        if status != nil {
            statusPresentation = .cached
            message = "Actualisation impossible. Le dernier état connu est conservé."
        } else {
            statusPresentation = .unavailable
            message = failureMessage
        }
    }

    private func savePairedMacs() {
        UserDefaults.standard.set(
            try? JSONEncoder.capoteRemote.encode(pairedMacs),
            forKey: DefaultsKey.pairedMacs
        )
    }

    private func adoptTailscaleHost(_ value: String?, for identifier: UUID) {
        guard let value,
              let normalized = RemoteDirectAccess.normalizedTailscaleHost(value),
              let index = pairedMacs.firstIndex(where: { $0.id == identifier }),
              pairedMacs[index].tailscaleHost != normalized else {
            return
        }

        pairedMacs[index].tailscaleHost = normalized
        if selectedMac?.id == identifier {
            selectedMac = pairedMacs[index]
        }
        savePairedMacs()
    }

    private func persistSelectedMac() {
        let defaults = UserDefaults.standard
        if let selectedMac {
            defaults.set(selectedMac.id.uuidString, forKey: DefaultsKey.selectedMac)
        } else {
            defaults.removeObject(forKey: DefaultsKey.selectedMac)
        }
    }

    private func cancelConnection(message: String?) {
        activeRequestIdentifier = nil
        isConnecting = false
        if let message {
            self.message = message
        }
    }

}

private enum CompanionError: Error {
    case unexpectedResponse
    case pairingRejected
    case remoteRejected
}

private enum CompanionNetworkParameters {
    static func localTCP() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        parameters.includePeerToPeer = true
        return parameters
    }
}

private struct SocketCompanionTransport: CompanionTransport {
    let endpoint: NWEndpoint
    let connectionLabel: String
    let parameters: NWParameters

    func send(
        _ wire: RemoteWireMessage,
        completion: @escaping (Result<CompanionTransportResponse, Error>) -> Void
    ) {
        do {
            let frame = try RemoteFrameCodec.encode(wire)
            SocketRequestSession(endpoint: endpoint, parameters: parameters, frame: frame) { result in
                completion(result.map {
                    CompanionTransportResponse(wire: $0, connectionLabel: connectionLabel)
                })
            }.start()
        } catch {
            completion(.failure(error))
        }
    }
}

private struct AdaptiveCompanionTransport: CompanionTransport {
    let transports: [SocketCompanionTransport]

    var connectionLabel: String {
        transports.map(\.connectionLabel).joined(separator: " ou ")
    }

    func send(
        _ wire: RemoteWireMessage,
        completion: @escaping (Result<CompanionTransportResponse, Error>) -> Void
    ) {
        FirstSuccessfulCompanionTransportSession(
            transports: transports,
            wire: wire,
            completion: completion
        ).start()
    }
}

private final class FirstSuccessfulCompanionTransportSession {
    private let transports: [SocketCompanionTransport]
    private let wire: RemoteWireMessage
    private let completion: (Result<CompanionTransportResponse, Error>) -> Void
    private let queue = DispatchQueue(label: "fr.benjaminfarrudja.capote.companion-adaptive-transport")
    private var completed = false
    private var resultCount = 0
    private var fallbackResult: Result<CompanionTransportResponse, Error>?

    init(
        transports: [SocketCompanionTransport],
        wire: RemoteWireMessage,
        completion: @escaping (Result<CompanionTransportResponse, Error>) -> Void
    ) {
        self.transports = transports
        self.wire = wire
        self.completion = completion
    }

    func start() {
        for (index, transport) in transports.enumerated() {
            queue.asyncAfter(deadline: .now() + .milliseconds(index * 250)) { [self] in
                guard !completed else { return }
                transport.send(wire) { [self] result in
                    queue.async { [self] in
                        receive(result)
                    }
                }
            }
        }
        queue.asyncAfter(deadline: .now() + 6) { [self] in
            finish(fallbackResult ?? .failure(CompanionError.unexpectedResponse))
        }
    }

    private func receive(_ result: Result<CompanionTransportResponse, Error>) {
        guard !completed else { return }
        resultCount += 1

        if case .success(let response) = result, response.wire.kind != .error {
            finish(result)
            return
        }

        fallbackResult = result
        if resultCount == transports.count {
            finish(result)
        }
    }

    private func finish(_ result: Result<CompanionTransportResponse, Error>) {
        guard !completed else { return }
        completed = true
        completion(result)
    }
}

private final class SocketRequestSession {
    private let connection: NWConnection
    private let frame: Data
    private let completion: (Result<RemoteWireMessage, Error>) -> Void
    private let queue = DispatchQueue(label: "fr.benjaminfarrudja.capote.companion-request")
    private var completed = false

    init(
        endpoint: NWEndpoint,
        parameters: NWParameters,
        frame: Data,
        completion: @escaping (Result<RemoteWireMessage, Error>) -> Void
    ) {
        self.connection = NWConnection(to: endpoint, using: parameters)
        self.frame = frame
        self.completion = completion
    }

    func start() {
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.connection.send(content: self.frame, completion: .contentProcessed { error in
                    if let error { self.finish(.failure(error)) } else { self.receiveHeader() }
                })
            case .failed(let error):
                self.finish(.failure(error))
            case .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.finish(.failure(CompanionError.unexpectedResponse))
        }
    }

    private func receiveHeader() {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, _, error in
            guard let self else { return }
            guard error == nil, let header = data, header.count == 4 else {
                self.finish(.failure(error ?? CompanionError.unexpectedResponse))
                return
            }
            let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= CapoteRemoteProtocol.maximumFrameSize else {
                self.finish(.failure(CompanionError.unexpectedResponse))
                return
            }
            self.connection.receive(minimumIncompleteLength: Int(length), maximumLength: Int(length)) {
                [weak self] data, _, _, error in
                guard let self else { return }
                do {
                    guard error == nil, let data, data.count == Int(length) else {
                        throw error ?? CompanionError.unexpectedResponse
                    }
                    self.finish(.success(try RemoteFrameCodec.decode(header + data)))
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    private func finish(_ result: Result<RemoteWireMessage, Error>) {
        guard !completed else { return }
        completed = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        completion(result)
    }
}
