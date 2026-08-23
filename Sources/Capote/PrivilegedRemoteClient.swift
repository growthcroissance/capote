import Foundation
import Security
import ServiceManagement
#if SWIFT_PACKAGE
import CapoteRemoteCore
#endif

@objc protocol CapotePrivilegedRemoteXPC {
    func perform(_ requestData: Data, withReply reply: @escaping (Data) -> Void)
}

enum PrivilegedRemoteServiceStatus: Equatable {
    case unavailableSignature
    case notRegistered
    case requiresApproval
    case enabled
    case unknown
}

final class PrivilegedRemoteClient: @unchecked Sendable {
    static let shared = PrivilegedRemoteClient()

    private var service: SMAppService {
        SMAppService.daemon(plistName: CapotePrivilegedRemoteProtocol.plistName)
    }

    var hasStableSignature: Bool {
        guard let identity = StableSigningIdentity.current() else { return false }
        return identity.identifier == CapotePrivilegedRemoteProtocol.applicationIdentifier
            && !identity.teamIdentifier.isEmpty
    }

    var status: PrivilegedRemoteServiceStatus {
        guard hasStableSignature else { return .unavailableSignature }
        switch service.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notRegistered
        @unknown default: return .unknown
        }
    }

    func register() throws {
        guard hasStableSignature else { throw PrivilegedRemoteClientError.stableSignatureRequired }
        try service.register()
    }

    func unregister() throws {
        guard hasStableSignature else { throw PrivilegedRemoteClientError.stableSignatureRequired }
        try service.unregister()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func perform(
        _ request: PrivilegedRemoteRequest,
        completion: @escaping @Sendable (Result<PrivilegedRemoteResponse, Error>) -> Void
    ) {
        let replyOnce = PrivilegedReplyOnce(completion)
        guard status == .enabled else {
            replyOnce.finish(.failure(PrivilegedRemoteClientError.serviceUnavailable))
            return
        }

        do {
            let requestData = try JSONEncoder.capoteRemote.encode(request)
            let connection = NSXPCConnection(
                machServiceName: CapotePrivilegedRemoteProtocol.machServiceName,
                options: .privileged
            )
            connection.remoteObjectInterface = NSXPCInterface(with: CapotePrivilegedRemoteXPC.self)
            connection.interruptionHandler = {
                replyOnce.finish(.failure(PrivilegedRemoteClientError.connectionInterrupted))
            }
            connection.invalidationHandler = nil
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                replyOnce.finish(.failure(error))
            }) as? CapotePrivilegedRemoteXPC else {
                connection.invalidate()
                replyOnce.finish(.failure(PrivilegedRemoteClientError.invalidProxy))
                return
            }
            proxy.perform(requestData) { data in
                defer { connection.invalidate() }
                do {
                    replyOnce.finish(
                        .success(try JSONDecoder.capoteRemote.decode(PrivilegedRemoteResponse.self, from: data))
                    )
                } catch {
                    replyOnce.finish(.failure(error))
                }
            }
        } catch {
            replyOnce.finish(.failure(error))
        }
    }
}

private final class PrivilegedReplyOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<PrivilegedRemoteResponse, Error>) -> Void)?

    init(_ completion: @escaping @Sendable (Result<PrivilegedRemoteResponse, Error>) -> Void) {
        self.completion = completion
    }

    func finish(_ result: Result<PrivilegedRemoteResponse, Error>) {
        lock.lock()
        let completion = self.completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }
}

private struct StableSigningIdentity {
    let identifier: String
    let teamIdentifier: String

    static func current() -> StableSigningIdentity? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode,
              SecStaticCodeCheckValidity(staticCode, [], nil) == errSecSuccess else {
            return nil
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &information) == errSecSuccess,
              let values = information as? [CFString: Any],
              let identifier = values[kSecCodeInfoIdentifier] as? String,
              let teamIdentifier = values[kSecCodeInfoTeamIdentifier] as? String else {
            return nil
        }
        return StableSigningIdentity(identifier: identifier, teamIdentifier: teamIdentifier)
    }
}

enum PrivilegedRemoteClientError: Error {
    case stableSignatureRequired
    case serviceUnavailable
    case connectionInterrupted
    case invalidProxy
}
