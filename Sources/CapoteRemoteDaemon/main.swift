import Darwin
import Foundation
import Security
#if SWIFT_PACKAGE
import CapoteRemoteCore
#endif

@objc private protocol CapotePrivilegedRemoteXPC {
    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

private final class SigningValidator {
    private let ownTeamIdentifier: String?

    init() {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        if SecCodeCopySelf([], &code) == errSecSuccess,
           let code,
           SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
           let staticCode,
           SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
           let values = information as? [CFString: Any] {
            ownTeamIdentifier = values[kSecCodeInfoTeamIdentifier] as? String
        } else {
            ownTeamIdentifier = nil
        }
    }

    func accepts(_ connection: NSXPCConnection) -> Bool {
        guard let ownTeamIdentifier, !ownTeamIdentifier.isEmpty else { return false }
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        var guest: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &guest) == errSecSuccess,
              let guest,
              SecCodeCheckValidity(guest, [], nil) == errSecSuccess else {
            return false
        }
        var staticGuest: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopyStaticCode(guest, [], &staticGuest) == errSecSuccess,
              let staticGuest,
              SecCodeCopySigningInformation(staticGuest, [], &information) == errSecSuccess,
              let values = information as? [CFString: Any],
              values[kSecCodeInfoIdentifier] as? String == CapotePrivilegedRemoteProtocol.applicationIdentifier,
              values[kSecCodeInfoTeamIdentifier] as? String == ownTeamIdentifier else {
            return false
        }
        return true
    }
}

private final class RemotePowerService: NSObject, CapotePrivilegedRemoteXPC {
    private let queue = DispatchQueue(label: "fr.benjaminfarrudja.capote.remote-power")
    private let markerPath = "/Library/Application Support/Capote/remote-session"
    private var sessionEndDate: Date?
    private var timer: DispatchSourceTimer?
    private var thermalSafetyTriggered = false

    override init() {
        super.init()
        queue.sync {
            if FileManager.default.fileExists(atPath: markerPath) {
                _ = restoreSleep()
            }
            startSafetyTimer()
        }
    }

    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void) {
        queue.async {
            let response: PrivilegedRemoteResponse
            do {
                let request = try JSONDecoder.capoteRemote.decode(PrivilegedRemoteRequest.self, from: requestData)
                response = try self.perform(request)
            } catch {
                response = PrivilegedRemoteResponse(
                    requestIdentifier: UUID(),
                    accepted: false,
                    message: "Commande privilégiée refusée.",
                    isSleepDisabled: self.readSleepDisabled(),
                    sessionEndDate: self.sessionEndDate
                )
            }
            reply((try? JSONEncoder.capoteRemote.encode(response)) ?? Data())
        }
    }

    func restoreBeforeExit() {
        queue.sync { _ = restoreSleep() }
    }

    private func perform(_ request: PrivilegedRemoteRequest) throws -> PrivilegedRemoteResponse {
        switch request.action {
        case .status:
            return response(for: request, accepted: true, message: "État privilégié actualisé.")
        case .restoreSleep:
            let restored = restoreSleep()
            return response(
                for: request,
                accepted: restored,
                message: restored ? "Veille rétablie." : "Impossible de confirmer la restauration de la veille."
            )
        case .startDuration:
            guard let seconds = request.durationSeconds,
                  seconds >= 60,
                  TimeInterval(seconds) <= CapoteRemoteProtocol.maximumSessionDuration else {
                return response(for: request, accepted: false, message: "Durée distante refusée.")
            }
            guard ProcessInfo.processInfo.thermalState != .serious,
                  ProcessInfo.processInfo.thermalState != .critical else {
                thermalSafetyTriggered = true
                _ = restoreSleep()
                return response(for: request, accepted: false, message: "Session refusée pour sécurité thermique.")
            }
            try prepareMarker()
            do {
                try setSleepDisabled(true)
                guard readSleepDisabled() == true else {
                    throw RemoteDaemonError.pmsetFailed
                }
                sessionEndDate = Date().addingTimeInterval(TimeInterval(seconds))
                thermalSafetyTriggered = false
                return response(for: request, accepted: true, message: "Session distante démarrée.")
            } catch {
                try? setSleepDisabled(false)
                try? FileManager.default.removeItem(atPath: markerPath)
                throw error
            }
        }
    }

    private func response(
        for request: PrivilegedRemoteRequest,
        accepted: Bool,
        message: String
    ) -> PrivilegedRemoteResponse {
        PrivilegedRemoteResponse(
            requestIdentifier: request.identifier,
            accepted: accepted,
            message: message,
            isSleepDisabled: readSleepDisabled(),
            sessionEndDate: sessionEndDate,
            thermalSafetyTriggered: thermalSafetyTriggered
        )
    }

    private func startSafetyTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.sessionEndDate == nil,
               FileManager.default.fileExists(atPath: self.markerPath) {
                _ = self.restoreSleep()
                return
            }
            guard self.sessionEndDate != nil else { return }
            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .serious || thermal == .critical {
                self.thermalSafetyTriggered = true
                _ = self.restoreSleep()
            } else if let endDate = self.sessionEndDate, endDate <= Date() {
                _ = self.restoreSleep()
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func prepareMarker() throws {
        let directory = (markerPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        guard FileManager.default.createFile(
            atPath: markerPath,
            contents: Data("active\n".utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw RemoteDaemonError.markerCreationFailed
        }
    }

    @discardableResult
    private func restoreSleep() -> Bool {
        do {
            try setSleepDisabled(false)
            guard readSleepDisabled() == false else { return false }
            sessionEndDate = nil
            try? FileManager.default.removeItem(atPath: markerPath)
            return true
        } catch {
            return false
        }
    }

    private func setSleepDisabled(_ disabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw RemoteDaemonError.pmsetFailed }
    }

    private func readSleepDisabled() -> Bool? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "live"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            for line in text.split(whereSeparator: { $0.isNewline }) {
                let fields = line.split(whereSeparator: { $0.isWhitespace })
                if fields.count >= 2, fields[0] == "SleepDisabled" {
                    return fields[1] == "1"
                }
            }
        } catch {
            return nil
        }
        return nil
    }
}

private enum RemoteDaemonError: Error {
    case markerCreationFailed
    case pmsetFailed
}

private final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let validator = SigningValidator()
    private let service: RemotePowerService

    init(service: RemotePowerService) {
        self.service = service
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard validator.accepts(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: CapotePrivilegedRemoteXPC.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

@main
private struct CapoteRemoteDaemon {
    static func main() {
        guard getuid() == 0 else { exit(1) }
        let service = RemotePowerService()
        let delegate = ListenerDelegate(service: service)
        let listener = NSXPCListener(machServiceName: CapotePrivilegedRemoteProtocol.machServiceName)
        listener.delegate = delegate

        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler {
            service.restoreBeforeExit()
            exit(0)
        }
        termination.resume()
        listener.resume()
        RunLoop.main.run()
    }
}
