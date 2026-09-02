import XCTest
@testable import Capote
import CapoteRemoteCore

final class MacPowerStatusProviderTests: XCTestCase {
    func testSystemPowerSourceValuesAreMapped() {
        XCTAssertEqual(MacPowerStatusProvider.powerSource(from: "AC Power"), .externalPower)
        XCTAssertEqual(MacPowerStatusProvider.powerSource(from: "Battery Power"), .battery)
        XCTAssertNil(MacPowerStatusProvider.powerSource(from: "Off Line"))
        XCTAssertNil(MacPowerStatusProvider.powerSource(from: nil))
    }
}
