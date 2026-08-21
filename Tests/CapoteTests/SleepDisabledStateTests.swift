import Foundation
import ServiceManagement
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

struct SessionRecoveryPolicyTests {
    @Test func restoresOnlyTheExpectedBlockedSession() {
        let expectedURL = URL(fileURLWithPath: "/private/tmp/capote-session.cancel")

        #expect(SessionRecoveryPolicy.shouldRestoreDirectly(
            isSleepDisabled: true,
            currentCancellationURL: expectedURL,
            expectedCancellationURL: expectedURL
        ))
        #expect(!SessionRecoveryPolicy.shouldRestoreDirectly(
            isSleepDisabled: false,
            currentCancellationURL: expectedURL,
            expectedCancellationURL: expectedURL
        ))
        #expect(!SessionRecoveryPolicy.shouldRestoreDirectly(
            isSleepDisabled: true,
            currentCancellationURL: URL(fileURLWithPath: "/private/tmp/other-session.cancel"),
            expectedCancellationURL: expectedURL
        ))
    }
}

@MainActor
private final class LaunchAtLoginServiceMock: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }
}

struct LaunchAtLoginControllerTests {
    @Test func treatsAMissingInitialRecordAsNotRegistered() {
        #expect(LaunchAtLoginStatusMapper.map(.notFound) == .notRegistered)
    }

    @Test @MainActor func registersAndUnregistersThroughTheInjectedService() {
        let service = LaunchAtLoginServiceMock(status: .notRegistered)
        let controller = LaunchAtLoginController(service: service)

        controller.setRegistered(true)
        #expect(controller.status == .enabled)
        #expect(controller.isRegistered)

        controller.setRegistered(false)
        #expect(controller.status == .notRegistered)
        #expect(!controller.isRegistered)
    }

    @Test @MainActor func refreshesStatusAfterAnExternalChange() {
        let service = LaunchAtLoginServiceMock(status: .enabled)
        let controller = LaunchAtLoginController(service: service)

        service.status = .requiresApproval
        controller.refresh()

        #expect(controller.status == .requiresApproval)
        #expect(controller.isRegistered)
    }

    @Test @MainActor func reportsRegistrationErrorsAndKeepsTheSystemStatus() {
        let service = LaunchAtLoginServiceMock(status: .notRegistered)
        service.registerError = NSError(domain: "CapoteTests", code: 1)
        let controller = LaunchAtLoginController(service: service)

        controller.setRegistered(true)

        #expect(controller.status == .notRegistered)
        #expect(controller.errorMessage?.contains("Impossible d’activer") == true)
    }
}
