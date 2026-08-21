import Darwin
import Foundation

private enum SessionMode {
    case indefinite
    case duration(TimeInterval)
    case process(pid_t)
    case download(path: String, stableSeconds: TimeInterval)
}

private enum ThermalSafetyLevel: String {
    case serious = "thermal-serious"
    case critical = "thermal-critical"

    static var current: ThermalSafetyLevel? {
        switch ProcessInfo.processInfo.thermalState {
        case .serious: return .serious
        case .critical: return .critical
        case .nominal, .fair: return nil
        @unknown default: return .critical
        }
    }
}

private enum SessionEndReason {
    case conditionCompleted
    case cancelled
    case thermal(ThermalSafetyLevel)
}

private struct Options {
    let userUID: uid_t
    let cancelPath: String
    let resultPath: String
    let mode: SessionMode
    let dryRun: Bool
    let simulatedThermalLevel: ThermalSafetyLevel?

    static func parse(_ arguments: [String]) throws -> Options {
        var values: [String: String] = [:]
        var flags = Set<String>()
        var index = 0

        while index < arguments.count {
            let key = arguments[index]

            if key == "--dry-run" {
                flags.insert(key)
                index += 1
                continue
            }

            guard key.hasPrefix("--"), index + 1 < arguments.count else {
                throw HelperError.invalidArguments
            }

            values[key] = arguments[index + 1]
            index += 2
        }

        guard let rawUserUID = values["--user-uid"],
              let userUID = uid_t(rawUserUID),
              userUID > 0 else {
            throw HelperError.invalidArguments
        }

        let cancelPrefix = "/private/tmp/fr.benjaminfarrudja.capote-\(userUID)-"
        guard let cancelPath = decodeBase64(values["--cancel-base64"]),
              cancelPath.hasPrefix(cancelPrefix),
              cancelPath.hasSuffix(".cancel"),
              !cancelPath.dropFirst(cancelPrefix.count).contains("/") else {
            throw HelperError.invalidCancelPath
        }

        guard let resultPath = decodeBase64(values["--result-base64"]),
              resultPath.hasPrefix(cancelPrefix),
              resultPath.hasSuffix(".result"),
              !resultPath.dropFirst(cancelPrefix.count).contains("/"),
              resultPath.dropLast(".result".count) == cancelPath.dropLast(".cancel".count) else {
            throw HelperError.invalidResultPath
        }

        let mode: SessionMode
        switch values["--mode"] {
        case "indefinite":
            mode = .indefinite
        case "duration":
            guard let raw = values["--seconds"], let seconds = TimeInterval(raw), seconds > 0 else {
                throw HelperError.invalidArguments
            }
            mode = .duration(seconds)
        case "process":
            guard let raw = values["--pid"], let pid = pid_t(raw), pid > 0 else {
                throw HelperError.invalidArguments
            }
            mode = .process(pid)
        case "download":
            guard let path = decodeBase64(values["--path-base64"]),
                  path.hasPrefix("/"),
                  let rawDelay = values["--stable-seconds"],
                  let delay = TimeInterval(rawDelay),
                  delay > 0 else {
                throw HelperError.invalidArguments
            }
            mode = .download(path: path, stableSeconds: delay)
        default:
            throw HelperError.invalidArguments
        }

        let dryRun = flags.contains("--dry-run")
        let simulatedThermalLevel: ThermalSafetyLevel?

        if let rawLevel = values["--simulate-thermal"] {
            guard dryRun, let level = ThermalSafetyLevel(rawValue: "thermal-\(rawLevel)") else {
                throw HelperError.invalidArguments
            }
            simulatedThermalLevel = level
        } else {
            simulatedThermalLevel = nil
        }

        return Options(
            userUID: userUID,
            cancelPath: cancelPath,
            resultPath: resultPath,
            mode: mode,
            dryRun: dryRun,
            simulatedThermalLevel: simulatedThermalLevel
        )
    }

    private static func decodeBase64(_ value: String?) -> String? {
        guard let value, let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private enum HelperError: Error {
    case invalidArguments
    case invalidCancelPath
    case invalidResultPath
    case administratorRequired
    case activeSessionAlreadyRunning
    case invalidSessionLock
    case pmsetFailed(Int32)
}

private final class SessionLock {
    private var descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    static func acquire(dryRun: Bool, userUID: uid_t) throws -> SessionLock {
        let path: String
        let expectedOwner: uid_t

        if dryRun {
            path = "/private/tmp/fr.benjaminfarrudja.capote-\(userUID)-dry-run.lock"
            expectedOwner = userUID
        } else {
            path = "/var/run/fr.benjaminfarrudja.capote.session.lock"
            expectedOwner = 0
        }

        let descriptor = open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw HelperError.invalidSessionLock
        }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              fileInfo.st_mode & S_IFMT == S_IFREG,
              fileInfo.st_uid == expectedOwner else {
            close(descriptor)
            throw HelperError.invalidSessionLock
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw HelperError.activeSessionAlreadyRunning
        }

        return SessionLock(descriptor: descriptor)
    }

    func release() {
        guard descriptor >= 0 else { return }
        flock(descriptor, LOCK_UN)
        close(descriptor)
        descriptor = -1
    }

    deinit {
        release()
    }
}

private final class CancellationState {
    private let lock = NSLock()
    private var requested = false

    func request() {
        lock.lock()
        requested = true
        lock.unlock()
    }

    func isRequested() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }
}

private struct FileSignature: Equatable {
    let size: UInt64
    let modificationTime: TimeInterval

    static func read(path: String) -> FileSignature? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }

        if !isDirectory.boolValue {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                return nil
            }
            return signature(from: attributes)
        }

        guard let enumerator = FileManager.default.enumerator(atPath: path) else {
            return nil
        }

        var totalSize: UInt64 = 0
        var latestModification: TimeInterval = 0

        while let child = enumerator.nextObject() as? String {
            let childPath = (path as NSString).appendingPathComponent(child)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: childPath) else {
                continue
            }
            let signature = signature(from: attributes)
            totalSize &+= signature.size
            latestModification = max(latestModification, signature.modificationTime)
        }

        return FileSignature(size: totalSize, modificationTime: latestModification)
    }

    private static func signature(from attributes: [FileAttributeKey: Any]) -> FileSignature {
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let date = attributes[.modificationDate] as? Date ?? .distantPast
        return FileSignature(size: size, modificationTime: date.timeIntervalSince1970)
    }
}

@main
private struct CapoteSessionHelper {
    static func main() {
        do {
            let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
            try run(options)
        } catch {
            fputs("CapoteSession: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run(_ options: Options) throws {
        guard options.dryRun || getuid() == 0 else {
            throw HelperError.administratorRequired
        }

        let sessionLock = try SessionLock.acquire(dryRun: options.dryRun, userUID: options.userUID)
        defer { sessionLock.release() }

        let cancellationState = CancellationState()
        let signalSources = installSignalHandlers(cancellationState)
        _ = signalSources

        defer {
            try? FileManager.default.removeItem(atPath: options.cancelPath)
        }

        if options.dryRun {
            let reason = monitor(options, cancellationState: cancellationState)
            try recordIfNeeded(reason, atPath: options.resultPath, ownerUID: options.userUID)
            return
        }

        try setSleepDisabled(true)

        do {
            let reason = monitor(options, cancellationState: cancellationState)
            try setSleepDisabled(false)
            try recordIfNeeded(reason, atPath: options.resultPath, ownerUID: options.userUID)
        } catch {
            try? setSleepDisabled(false)
            throw error
        }
    }

    private static func monitor(_ options: Options, cancellationState: CancellationState) -> SessionEndReason {
        let startedAt = Date()
        var lastSignature: FileSignature?
        var stableSince = Date()

        while true {
            let thermalLevel = options.simulatedThermalLevel ?? (options.dryRun ? nil : ThermalSafetyLevel.current)
            if let thermalLevel {
                return .thermal(thermalLevel)
            }

            if cancellationState.isRequested() || FileManager.default.fileExists(atPath: options.cancelPath) {
                return .cancelled
            }

            switch options.mode {
            case .indefinite:
                break
            case .duration(let seconds):
                if Date().timeIntervalSince(startedAt) >= seconds { return .conditionCompleted }
            case .process(let pid):
                if kill(pid, 0) != 0 && errno != EPERM { return .conditionCompleted }
            case .download(let path, let stableSeconds):
                guard let signature = FileSignature.read(path: path) else { return .conditionCompleted }

                if signature != lastSignature {
                    lastSignature = signature
                    stableSince = Date()
                } else if Date().timeIntervalSince(stableSince) >= stableSeconds {
                    return .conditionCompleted
                }
            }

            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private static func recordIfNeeded(
        _ reason: SessionEndReason,
        atPath path: String,
        ownerUID: uid_t
    ) throws {
        guard case .thermal(let level) = reason else {
            return
        }

        let descriptor = open(path, O_WRONLY | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw HelperError.invalidResultPath
        }
        defer { close(descriptor) }

        var fileInfo = stat()
        guard fstat(descriptor, &fileInfo) == 0,
              fileInfo.st_mode & S_IFMT == S_IFREG,
              fileInfo.st_uid == ownerUID,
              ftruncate(descriptor, 0) == 0 else {
            throw HelperError.invalidResultPath
        }

        let data = Data(level.rawValue.utf8)
        let bytesWritten = data.withUnsafeBytes { buffer in
            write(descriptor, buffer.baseAddress, buffer.count)
        }
        guard bytesWritten == data.count, fsync(descriptor) == 0 else {
            throw HelperError.invalidResultPath
        }
    }

    private static func setSleepDisabled(_ disabled: Bool) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-a", "disablesleep", disabled ? "1" : "0"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HelperError.pmsetFailed(process.terminationStatus)
        }
    }

    private static func installSignalHandlers(_ state: CancellationState) -> [DispatchSourceSignal] {
        [SIGTERM, SIGINT, SIGHUP].map { signalNumber in
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
            source.setEventHandler {
                state.request()
            }
            source.resume()
            return source
        }
    }
}
