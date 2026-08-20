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
