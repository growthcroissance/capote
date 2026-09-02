import Foundation

public enum CapoteRemoteProtocol {
    public static let version = 1
    public static let bonjourType = "_capote._tcp"
    public static let maximumFrameSize = 64 * 1_024
    public static let commandLifetime: TimeInterval = 30
}

public enum RemoteCommandAction: String, Codable, CaseIterable, Sendable {
    case status
    case restoreSleep
}

public struct RemoteCommand: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let identifier: UUID
    public let issuedAt: Date
    public let expiresAt: Date
    public let action: RemoteCommandAction

    public init(
        identifier: UUID = UUID(),
        issuedAt: Date = Date(),
        lifetime: TimeInterval = CapoteRemoteProtocol.commandLifetime,
        action: RemoteCommandAction
    ) {
        self.protocolVersion = CapoteRemoteProtocol.version
        self.identifier = identifier
        self.issuedAt = issuedAt
        self.expiresAt = issuedAt.addingTimeInterval(lifetime)
        self.action = action
    }
}

public enum RemoteCommandValidationError: Error, Equatable, LocalizedError {
    case unsupportedProtocol
    case expired
    case issuedInFuture
    case replayed

    public var errorDescription: String? {
        switch self {
        case .unsupportedProtocol: return "Version du protocole non prise en charge."
        case .expired: return "Commande distante expirée."
        case .issuedInFuture: return "Horloge de l’appareil distant incohérente."
        case .replayed: return "Commande distante déjà traitée."
        }
    }
}

public final class RemoteCommandValidator: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedIdentifiers: [UUID: Date] = [:]
    private let allowedClockSkew: TimeInterval

    public init(allowedClockSkew: TimeInterval = 10) {
        self.allowedClockSkew = allowedClockSkew
    }

    public func validate(_ command: RemoteCommand, now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }

        acceptedIdentifiers = acceptedIdentifiers.filter { $0.value > now }

        guard command.protocolVersion == CapoteRemoteProtocol.version else {
            throw RemoteCommandValidationError.unsupportedProtocol
        }
        guard command.issuedAt <= now.addingTimeInterval(allowedClockSkew) else {
            throw RemoteCommandValidationError.issuedInFuture
        }
        let lifetime = command.expiresAt.timeIntervalSince(command.issuedAt)
        guard command.expiresAt > now,
              lifetime > 0,
              lifetime <= CapoteRemoteProtocol.commandLifetime else {
            throw RemoteCommandValidationError.expired
        }
        guard acceptedIdentifiers[command.identifier] == nil else {
            throw RemoteCommandValidationError.replayed
        }

        acceptedIdentifiers[command.identifier] = command.expiresAt
    }
}

public enum RemoteThermalState: String, Codable, Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical
    case unknown
}

public struct RemoteMacStatus: Codable, Equatable, Sendable {
    public let isSleepDisabled: Bool?
    public let canRestoreActiveSession: Bool
    public let activeSessionDescription: String?
    public let sessionEndDate: Date?
    public let thermalSafetyTriggered: Bool
    public let thermalState: RemoteThermalState?
    public let tailscaleHost: String?

    public init(
        isSleepDisabled: Bool?,
        canRestoreActiveSession: Bool,
        activeSessionDescription: String?,
        sessionEndDate: Date?,
        thermalSafetyTriggered: Bool = false,
        thermalState: RemoteThermalState? = nil,
        tailscaleHost: String? = nil
    ) {
        self.isSleepDisabled = isSleepDisabled
        self.canRestoreActiveSession = canRestoreActiveSession
        self.activeSessionDescription = activeSessionDescription
        self.sessionEndDate = sessionEndDate
        self.thermalSafetyTriggered = thermalSafetyTriggered
        self.thermalState = thermalState
        self.tailscaleHost = tailscaleHost
    }
}

public struct RemoteResponse: Codable, Equatable, Sendable {
    public let commandIdentifier: UUID
    public let accepted: Bool
    public let message: String
    public let status: RemoteMacStatus?

    public init(commandIdentifier: UUID, accepted: Bool, message: String, status: RemoteMacStatus?) {
        self.commandIdentifier = commandIdentifier
        self.accepted = accepted
        self.message = message
        self.status = status
    }
}

public enum RemoteWireKind: String, Codable, Sendable {
    case pairRequest
    case pairResponse
    case command
    case response
    case error
}

public struct RemoteWireMessage: Codable, Equatable, Sendable {
    public let kind: RemoteWireKind
    public let payload: Data

    public init(kind: RemoteWireKind, payload: Data) {
        self.kind = kind
        self.payload = payload
    }
}

public struct PairRequest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let serviceIdentifier: UUID
    public let deviceIdentifier: UUID
    public let deviceName: String
    public let nonce: Data
    public let proof: Data

    public init(
        serviceIdentifier: UUID,
        deviceIdentifier: UUID,
        deviceName: String,
        nonce: Data,
        proof: Data
    ) {
        self.protocolVersion = CapoteRemoteProtocol.version
        self.serviceIdentifier = serviceIdentifier
        self.deviceIdentifier = deviceIdentifier
        self.deviceName = deviceName
        self.nonce = nonce
        self.proof = proof
    }
}

public struct PairResponse: Codable, Equatable, Sendable {
    public let accepted: Bool
    public let serviceIdentifier: UUID
    public let macName: String
    public let encryptedDeviceKey: Data?
    public let message: String

    public init(
        accepted: Bool,
        serviceIdentifier: UUID,
        macName: String,
        encryptedDeviceKey: Data?,
        message: String
    ) {
        self.accepted = accepted
        self.serviceIdentifier = serviceIdentifier
        self.macName = macName
        self.encryptedDeviceKey = encryptedDeviceKey
        self.message = message
    }
}

public struct EncryptedRemotePayload: Codable, Equatable, Sendable {
    public let deviceIdentifier: UUID
    public let sealedPayload: Data

    public init(deviceIdentifier: UUID, sealedPayload: Data) {
        self.deviceIdentifier = deviceIdentifier
        self.sealedPayload = sealedPayload
    }
}
