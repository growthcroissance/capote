import Foundation
import Network

public enum RemoteDirectAccess {
    public static let port: UInt16 = 51_684

    public enum Route: Equatable, Sendable {
        case tailscale
        case localNetwork
    }

    public static func preferredRoutes(
        hasTailscaleHost: Bool,
        hasLocalEndpoint: Bool
    ) -> [Route] {
        var routes: [Route] = []
        if hasLocalEndpoint {
            routes.append(.localNetwork)
        }
        if hasTailscaleHost {
            routes.append(.tailscale)
        }
        return routes
    }

    public static func normalizedTailscaleHost(_ value: String) -> String? {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasSuffix(".") {
            host.removeLast()
        }
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }

        if let address = IPv4Address(host), isTailscaleIPv4(address) {
            return host
        }
        if let address = IPv6Address(host), isTailscaleIPv6(address) {
            return host
        }
        guard host.hasSuffix(".ts.net"), isValidDNSName(host) else {
            return nil
        }
        return host
    }

    private static func isTailscaleIPv4(_ address: IPv4Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        return bytes.count == 4 && bytes[0] == 100 && (64...127).contains(bytes[1])
    }

    private static func isTailscaleIPv6(_ address: IPv6Address) -> Bool {
        let bytes = [UInt8](address.rawValue)
        let prefix: [UInt8] = [0xfd, 0x7a, 0x11, 0x5c, 0xa1, 0xe0]
        return bytes.count == 16 && Array(bytes.prefix(prefix.count)) == prefix
    }

    private static func isValidDNSName(_ host: String) -> Bool {
        guard host.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 4 else { return false }

        return labels.allSatisfy { label in
            guard !label.isEmpty,
                  label.count <= 63,
                  label.first != "-",
                  label.last != "-" else {
                return false
            }
            return label.allSatisfy { character in
                character.isASCII && (character.isLetter || character.isNumber || character == "-")
            }
        }
    }
}

public enum CompanionSelectionPolicy {
    public static func selectedIdentifier(
        persistedIdentifier: UUID?,
        availableIdentifiers: [UUID]
    ) -> UUID? {
        if let persistedIdentifier,
           availableIdentifiers.contains(persistedIdentifier) {
            return persistedIdentifier
        }
        return availableIdentifiers.first
    }
}
