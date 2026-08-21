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
