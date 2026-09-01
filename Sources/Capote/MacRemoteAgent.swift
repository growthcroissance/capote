import Foundation
import Network
#if SWIFT_PACKAGE
import CapoteRemoteCore
#endif

struct RemoteExecutionResult: Sendable {
    let accepted: Bool
    let message: String
    let status: RemoteMacStatus
}

final class MacRemoteAgent: @unchecked Sendable {
    typealias CommandHandler = @Sendable (RemoteCommand, @escaping @Sendable (RemoteExecutionResult) -> Void) -> Void
    typealias EventHandler = @Sendable (String) -> Void

    let serviceIdentifier: UUID
    private let queue = DispatchQueue(label: "fr.benjaminfarrudja.capote.remote-agent")
    private let keyStore: RemoteDeviceKeyStore
    private let validator = RemoteCommandValidator()
    private let commandHandler: CommandHandler
    private let eventHandler: EventHandler
    private var listener: NWListener?
    private var pairingCode: String?
    private var pairingAttempts = 0

    init(
        serviceIdentifier: UUID,
        keyStore: RemoteDeviceKeyStore,
        commandHandler: @escaping CommandHandler,
        eventHandler: @escaping EventHandler
    ) {
        self.serviceIdentifier = serviceIdentifier
        self.keyStore = keyStore
        self.commandHandler = commandHandler
        self.eventHandler = eventHandler
    }

    func start() throws {
        guard let port = NWEndpoint.Port(rawValue: RemoteDirectAccess.port) else {
            throw RemoteAgentError.invalidPort
        }
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(
            name: serviceIdentifier.uuidString,
            type: CapoteRemoteProtocol.bonjourType
        )
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.eventHandler(
                    "Contrôle iPhone disponible localement et via Tailscale sur le port \(RemoteDirectAccess.port)."
                )
            case .failed(let error):
                self.eventHandler("Contrôle iPhone indisponible : \(error.localizedDescription)")
                self.stop()
            case .cancelled:
                self.eventHandler("Contrôle iPhone arrêté.")
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    func stop() {
        queue.async { [self] in
            pairingCode = nil
            listener?.cancel()
            listener = nil
        }
    }

    func beginPairing() throws -> String {
        let code = try RemoteControlCrypto.makePairingCode()
        queue.sync {
            pairingCode = code
            pairingAttempts = 0
        }
        return code
    }

    func cancelPairing() {
        queue.sync {
            pairingCode = nil
            pairingAttempts = 0
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.receiveHeader(on: connection)
            case .failed, .cancelled:
                connection.cancel()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveHeader(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, complete, error in
            guard let self,
                  error == nil,
                  !complete,
                  let data,
                  data.count == 4 else {
                connection.cancel()
                return
            }
            let length = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard length > 0, length <= CapoteRemoteProtocol.maximumFrameSize else {
                self.sendError("Trame distante invalide.", on: connection)
                return
            }
            self.receivePayload(length: Int(length), header: data, on: connection)
        }
    }

    private func receivePayload(length: Int, header: Data, on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, data.count == length else {
                connection.cancel()
                return
            }
            do {
                let message = try RemoteFrameCodec.decode(header + data)
                try self.process(message, on: connection)
            } catch {
                self.sendError("Requête distante refusée.", on: connection)
            }
        }
    }

    private func process(_ message: RemoteWireMessage, on connection: NWConnection) throws {
        switch message.kind {
        case .pairRequest:
            try processPairRequest(message.payload, on: connection)
        case .command:
            try processCommand(message.payload, on: connection)
        case .pairResponse, .response, .error:
            sendError("Type de requête inattendu.", on: connection)
        }
    }

    private func processPairRequest(_ payload: Data, on connection: NWConnection) throws {
        guard pairingAttempts < 5, let pairingCode else {
            throw RemoteAgentError.pairingUnavailable
        }
        pairingAttempts += 1

        let request = try JSONDecoder.capoteRemote.decode(PairRequest.self, from: payload)
        guard request.serviceIdentifier == serviceIdentifier else {
            throw RemoteAgentError.wrongService
        }
        try RemoteControlCrypto.verifyPairRequest(request, pairingCode: pairingCode)

        let deviceKey = try RemoteControlCrypto.randomData(count: 32)
        let device = PairedRemoteDevice(id: request.deviceIdentifier, name: request.deviceName, pairedAt: Date())
        try keyStore.save(key: deviceKey, for: device)
        let encryptedKey = try RemoteControlCrypto.sealDeviceKey(
            deviceKey,
            pairingCode: pairingCode,
            nonce: request.nonce
        )
        let response = PairResponse(
            accepted: true,
            serviceIdentifier: serviceIdentifier,
            macName: Host.current().localizedName ?? "Mac",
            encryptedDeviceKey: encryptedKey,
            message: "iPhone jumelé avec Capote."
        )
        self.pairingCode = nil
        send(
            RemoteWireMessage(kind: .pairResponse, payload: try JSONEncoder.capoteRemote.encode(response)),
            on: connection
        )
        eventHandler("\(request.deviceName) est maintenant jumelé.")
    }

    private func processCommand(_ payload: Data, on connection: NWConnection) throws {
        let encrypted = try JSONDecoder.capoteRemote.decode(EncryptedRemotePayload.self, from: payload)
        guard let deviceKey = keyStore.key(for: encrypted.deviceIdentifier) else {
            throw RemoteAgentError.unknownDevice
        }
        let command = try RemoteControlCrypto.open(
            RemoteCommand.self,
            from: encrypted.sealedPayload,
            using: deviceKey
        )
        try validator.validate(command)

        commandHandler(command) { [weak self] result in
            guard let self else { return }
            do {
                let response = RemoteResponse(
                    commandIdentifier: command.identifier,
                    accepted: result.accepted,
                    message: result.message,
                    status: result.status
                )
                let sealed = try RemoteControlCrypto.seal(response, using: deviceKey)
                let encryptedResponse = EncryptedRemotePayload(
                    deviceIdentifier: encrypted.deviceIdentifier,
                    sealedPayload: sealed
                )
                self.send(
                    RemoteWireMessage(
                        kind: .response,
                        payload: try JSONEncoder.capoteRemote.encode(encryptedResponse)
                    ),
                    on: connection
                )
            } catch {
                self.sendError("Impossible de chiffrer la réponse.", on: connection)
            }
        }
    }

    private func sendError(_ message: String, on connection: NWConnection) {
        let wire = RemoteWireMessage(kind: .error, payload: Data(message.utf8))
        send(wire, on: connection)
    }

    private func send(_ message: RemoteWireMessage, on connection: NWConnection) {
        do {
            let frame = try RemoteFrameCodec.encode(message)
            connection.send(content: frame, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }
}

private enum RemoteAgentError: Error {
    case invalidPort
    case pairingUnavailable
    case wrongService
    case unknownDevice
}
