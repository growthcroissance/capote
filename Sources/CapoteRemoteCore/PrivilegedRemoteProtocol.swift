import Foundation

public enum CapotePrivilegedRemoteProtocol {
    public static let machServiceName = "fr.benjaminfarrudja.capote.remote-daemon"
    public static let plistName = "fr.benjaminfarrudja.capote.remote-daemon.plist"
    public static let applicationIdentifier = "fr.benjaminfarrudja.capote"
}

public enum PrivilegedRemoteAction: String, Codable, Sendable {
    case status
    case startDuration
    case restoreSleep
}

public struct PrivilegedRemoteRequest: Codable, Equatable, Sendable {
    public let identifier: UUID
    public let action: PrivilegedRemoteAction
    public let durationSeconds: Int?

    public init(identifier: UUID = UUID(), action: PrivilegedRemoteAction, durationSeconds: Int? = nil) {
        self.identifier = identifier
        self.action = action
        self.durationSeconds = durationSeconds
    }
}

public struct PrivilegedRemoteResponse: Codable, Equatable, Sendable {
    public let requestIdentifier: UUID
    public let accepted: Bool
    public let message: String
    public let isSleepDisabled: Bool?
    public let sessionEndDate: Date?
    public let thermalSafetyTriggered: Bool

    public init(
        requestIdentifier: UUID,
        accepted: Bool,
        message: String,
        isSleepDisabled: Bool?,
        sessionEndDate: Date?,
        thermalSafetyTriggered: Bool = false
    ) {
        self.requestIdentifier = requestIdentifier
        self.accepted = accepted
        self.message = message
        self.isSleepDisabled = isSleepDisabled
        self.sessionEndDate = sessionEndDate
        self.thermalSafetyTriggered = thermalSafetyTriggered
    }
}
