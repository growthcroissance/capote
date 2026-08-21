import Foundation

struct AppVersion: Comparable, CustomStringConvertible, Equatable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let normalized = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)

        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2]),
              components.map(String.init) == [String(major), String(minor), String(patch)] else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let isDraft: Bool
    let isPrerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }
}

struct OfficialUpdate: Equatable {
    let version: AppVersion
    let releaseURL: URL
}

enum AppUpdateValidationError: Error {
    case invalidCurrentVersion
    case invalidRelease
}

enum AppUpdatePolicy {
    static let releasesURL = URL(string: "https://github.com/growthcroissance/capote/releases")!
    static let latestReleaseAPIURL = URL(
        string: "https://api.github.com/repos/growthcroissance/capote/releases/latest"
    )!

    static func availableUpdate(
        currentVersion value: String,
        release: GitHubRelease
    ) throws -> OfficialUpdate? {
        guard let currentVersion = AppVersion(value) else {
            throw AppUpdateValidationError.invalidCurrentVersion
        }

        guard !release.isDraft,
              !release.isPrerelease,
              let releaseVersion = AppVersion(release.tagName),
              isOfficialReleaseURL(release.htmlURL, tagName: release.tagName) else {
            throw AppUpdateValidationError.invalidRelease
        }

        guard releaseVersion > currentVersion else {
            return nil
        }

        return OfficialUpdate(version: releaseVersion, releaseURL: release.htmlURL)
    }

    private static func isOfficialReleaseURL(_ url: URL, tagName: String) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        return components.scheme == "https"
            && components.host?.lowercased() == "github.com"
            && components.port == nil
            && components.user == nil
            && components.password == nil
            && components.query == nil
            && components.fragment == nil
            && components.path == "/growthcroissance/capote/releases/tag/\(tagName)"
    }
}
