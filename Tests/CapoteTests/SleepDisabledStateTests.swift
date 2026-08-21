import Foundation
import Testing
@testable import Capote

struct SleepDisabledStateTests {
    @Test func parsesEnabledState() {
        let output = "System-wide power settings:\n SleepDisabled\t\t1\n"
        #expect(SleepDisabledState.parse(pmsetOutput: output) == true)
    }

    @Test func parsesDisabledState() {
        let output = "System-wide power settings:\n SleepDisabled\t\t0\n"
        #expect(SleepDisabledState.parse(pmsetOutput: output) == false)
    }

    @Test func rejectsMissingState() {
        #expect(SleepDisabledState.parse(pmsetOutput: "sleep 1\n") == nil)
    }
}

struct SessionTerminationReasonTests {
    @Test func parsesThermalSafetyReasons() {
        #expect(SessionTerminationReason.parse(Data("thermal-serious".utf8)) == .thermalSerious)
        #expect(SessionTerminationReason.parse(Data("thermal-critical\n".utf8)) == .thermalCritical)
    }

    @Test func rejectsUnknownReason() {
        #expect(SessionTerminationReason.parse(Data("condition-completed".utf8)) == nil)
    }
}

struct AppUpdatePolicyTests {
    @Test func comparesStableSemanticVersions() {
        #expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!)
        #expect(AppVersion("v2.0.0") == AppVersion("2.0.0"))
        #expect(AppVersion("1.0") == nil)
        #expect(AppVersion("1.0.0-beta") == nil)
        #expect(AppVersion("01.0.0") == nil)
    }

    @Test func acceptsOnlyNewerOfficialStableReleases() throws {
        let release = GitHubRelease(
            tagName: "v1.2.0",
            htmlURL: URL(string: "https://github.com/growthcroissance/capote/releases/tag/v1.2.0")!,
            isDraft: false,
            isPrerelease: false
        )

        #expect(
            try AppUpdatePolicy.availableUpdate(currentVersion: "1.1.0", release: release)?.version
                == AppVersion("1.2.0")
        )
        #expect(try AppUpdatePolicy.availableUpdate(currentVersion: "1.2.0", release: release) == nil)
    }

    @Test func rejectsUntrustedAndPrereleaseLinks() {
        let untrustedRelease = GitHubRelease(
            tagName: "v9.0.0",
            htmlURL: URL(string: "https://example.com/Capote.zip")!,
            isDraft: false,
            isPrerelease: false
        )
        let prerelease = GitHubRelease(
            tagName: "v2.0.0",
            htmlURL: URL(string: "https://github.com/growthcroissance/capote/releases/tag/v2.0.0")!,
            isDraft: false,
            isPrerelease: true
        )
        let mismatchedRelease = GitHubRelease(
            tagName: "v2.0.0",
            htmlURL: URL(string: "https://github.com/growthcroissance/capote/releases/tag/v1.9.0")!,
            isDraft: false,
            isPrerelease: false
        )

        #expect(throws: AppUpdateValidationError.self) {
            try AppUpdatePolicy.availableUpdate(currentVersion: "1.0.0", release: untrustedRelease)
        }
        #expect(throws: AppUpdateValidationError.self) {
            try AppUpdatePolicy.availableUpdate(currentVersion: "1.0.0", release: prerelease)
        }
        #expect(throws: AppUpdateValidationError.self) {
            try AppUpdatePolicy.availableUpdate(currentVersion: "1.0.0", release: mismatchedRelease)
        }
    }
}
