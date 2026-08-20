import Darwin
import Foundation

private enum SessionMode {
    case indefinite
    case duration(TimeInterval)
    case process(pid_t)
    case download(path: String, stableSeconds: TimeInterval)
}

private struct Options {
    let cancelPath: String
    let mode: SessionMode
    let dryRun: Bool

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

        let cancelPrefix = "/private/tmp/fr.benjaminfarrudja.capote-"
        guard let cancelPath = decodeBase64(values["--cancel-base64"]),
              cancelPath.hasPrefix(cancelPrefix),
              cancelPath.hasSuffix(".cancel"),
              !cancelPath.dropFirst(cancelPrefix.count).contains("/") else {
            throw HelperError.invalidCancelPath
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

        return Options(cancelPath: cancelPath, mode: mode, dryRun: flags.contains("--dry-run"))
    }

    private static func decodeBase64(_ value: String?) -> String? {
        guard let value, let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private enum HelperError: Error {
    case invalidArguments
    case invalidCancelPath
    case administratorRequired
    case pmsetFailed(Int32)
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

        let cancellationState = CancellationState()
        let signalSources = installSignalHandlers(cancellationState)
        _ = signalSources

        defer {
            try? FileManager.default.removeItem(atPath: options.cancelPath)
        }

        if options.dryRun {
            monitor(options, cancellationState: cancellationState)
            return
        }

        try setSleepDisabled(true)

        do {
            monitor(options, cancellationState: cancellationState)
            try setSleepDisabled(false)
        } catch {
            try? setSleepDisabled(false)
            throw error
        }
    }

    private static func monitor(_ options: Options, cancellationState: CancellationState) {
        let startedAt = Date()
        var lastSignature: FileSignature?
        var stableSince = Date()

        while true {
            if cancellationState.isRequested() || FileManager.default.fileExists(atPath: options.cancelPath) {
                return
            }

            switch options.mode {
            case .indefinite:
                break
            case .duration(let seconds):
                if Date().timeIntervalSince(startedAt) >= seconds { return }
            case .process(let pid):
                if kill(pid, 0) != 0 && errno != EPERM { return }
            case .download(let path, let stableSeconds):
                guard let signature = FileSignature.read(path: path) else { return }

                if signature != lastSignature {
                    lastSignature = signature
                    stableSince = Date()
                } else if Date().timeIntervalSince(stableSince) >= stableSeconds {
                    return
                }
            }

            Thread.sleep(forTimeInterval: 0.25)
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
