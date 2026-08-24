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
}

@MainActor
final class CompanionModel: ObservableObject {
    @Published private(set) var discoveredMacs: [DiscoveredMac] = []
    @Published private(set) var pairedMacs: [PairedMac] = []
    @Published private(set) var selectedMac: PairedMac?
    @Published private(set) var status: RemoteMacStatus?
    @Published private(set) var message: String?
    @Published private(set) var isConnecting = false

    private let browserQueue = DispatchQueue(label: "fr.benjaminfarrudja.capote.companion-browser")
    private let keyStore = CompanionKeyStore()
    private var browser: NWBrowser?

    private enum DefaultsKey {
        static let deviceIdentifier = "companion.deviceIdentifier"
        static let pairedMacs = "companion.pairedMacs"
        static let selectedMac = "companion.selectedMac"
    }

    var connectionText: String {
        if isConnecting { return "Connexion…" }
        guard let selectedMac else { return "Aucun Mac" }
        return endpoint(for: selectedMac.id) == nil ? "Hors ligne" : "Disponible"
    }

    var sleepStateText: String {
        switch status?.isSleepDisabled {
        case true: return "Désactivée"
        case false: return "Autorisée"
        case nil: return "Inconnu"
        }
    }

    init() {
        pairedMacs = Self.loadPairedMacs()
        if let selected = UserDefaults.standard.string(forKey: DefaultsKey.selectedMac),
           let identifier = UUID(uuidString: selected) {
            selectedMac = pairedMacs.first { $0.id == identifier }
        } else {
            selectedMac = pairedMacs.first
        }
    }

    func startBrowsing() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: CapoteRemoteProtocol.bonjourType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.compactMap { result -> (UUID, NWEndpoint)? in
                guard case .service(let name, _, _, _) = result.endpoint,
                      let identifier = UUID(uuidString: name) else { return nil }
                return (identifier, result.endpoint)
            }
            Task { @MainActor in
                guard let self else { return }
                self.discoveredMacs = endpoints.map { identifier, endpoint in
                    let displayName = self.pairedMacs.first(where: { $0.id == identifier })?.name
                        ?? "Mac avec Capote"
                    return DiscoveredMac(id: identifier, name: displayName, endpoint: endpoint)
                }.sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor in
                    self?.message = "Recherche locale impossible : \(error.localizedDescription)"
                }
            }
        }
        self.browser = browser
        browser.start(queue: browserQueue)
    }

    func refresh() {
        if selectedMac != nil { send(.status) }
    }

    func select(_ mac: PairedMac) {
        selectedMac = mac
        status = nil
        UserDefaults.standard.set(mac.id.uuidString, forKey: DefaultsKey.selectedMac)
        send(.status)
    }

    func pair(_ mac: DiscoveredMac, code: String, completion: @escaping (Bool) -> Void) {
        guard !isConnecting else { return }
        isConnecting = true
        message = nil

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
            sendWire(wire, to: mac.endpoint) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.isConnecting = false
                    do {
                        let responseWire = try result.get()
                        guard responseWire.kind == .pairResponse else { throw CompanionError.unexpectedResponse }
                        let response = try JSONDecoder.capoteRemote.decode(PairResponse.self, from: responseWire.payload)
                        guard response.accepted,
                              response.serviceIdentifier == mac.id,
                              let wrappedKey = response.encryptedDeviceKey else {
                            throw CompanionError.pairingRejected
                        }
                        let key = try RemoteControlCrypto.openDeviceKey(wrappedKey, pairingCode: code, nonce: nonce)
                        try self.keyStore.save(key: key, for: mac.id)
                        let paired = PairedMac(id: mac.id, name: response.macName)
                        self.pairedMacs.removeAll { $0.id == paired.id }
                        self.pairedMacs.append(paired)
                        self.savePairedMacs()
                        self.select(paired)
                        self.message = response.message
                        completion(true)
                    } catch {
                        self.message = "Jumelage refusé. Vérifiez le code affiché sur le Mac."
                        completion(false)
                    }
                }
            }
        } catch {
            isConnecting = false
            message = "Code de jumelage invalide."
            completion(false)
        }
    }

    func send(_ action: RemoteCommandAction) {
        guard !isConnecting,
              let mac = selectedMac,
              let endpoint = endpoint(for: mac.id),
              let key = keyStore.key(for: mac.id) else {
            message = "Ce Mac n’est pas disponible sur le réseau local."
            return
        }

        isConnecting = true
        message = nil
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
            sendWire(wire, to: endpoint) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.isConnecting = false
                    do {
                        let responseWire = try result.get()
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
                        self.message = response.message
                    } catch {
                        self.message = "Réponse du Mac invalide ou interrompue."
                    }
                }
            }
        } catch {
            isConnecting = false
            message = "Impossible de préparer la commande."
        }
    }

    func remove(_ mac: PairedMac) {
        keyStore.remove(for: mac.id)
        pairedMacs.removeAll { $0.id == mac.id }
        savePairedMacs()
        if selectedMac?.id == mac.id {
            selectedMac = pairedMacs.first
            status = nil
        }
    }

    private func endpoint(for identifier: UUID) -> NWEndpoint? {
        discoveredMacs.first { $0.id == identifier }?.endpoint
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

    private func savePairedMacs() {
        UserDefaults.standard.set(
            try? JSONEncoder.capoteRemote.encode(pairedMacs),
            forKey: DefaultsKey.pairedMacs
        )
    }

    private func sendWire(
        _ wire: RemoteWireMessage,
        to endpoint: NWEndpoint,
        completion: @escaping (Result<RemoteWireMessage, Error>) -> Void
    ) {
        do {
            let frame = try RemoteFrameCodec.encode(wire)
            RemoteRequestSession(endpoint: endpoint, frame: frame, completion: completion).start()
        } catch {
            completion(.failure(error))
        }
    }
}

private enum CompanionError: Error {
    case unexpectedResponse
    case pairingRejected
}

private final class RemoteRequestSession {
    private let connection: NWConnection
    private let frame: Data
    private let completion: (Result<RemoteWireMessage, Error>) -> Void
    private let queue = DispatchQueue(label: "fr.benjaminfarrudja.capote.companion-request")
    private var completed = false

    init(endpoint: NWEndpoint, frame: Data, completion: @escaping (Result<RemoteWireMessage, Error>) -> Void) {
        self.connection = NWConnection(to: endpoint, using: .tcp)
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
        queue.asyncAfter(deadline: .now() + 10) { [weak self] in
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
