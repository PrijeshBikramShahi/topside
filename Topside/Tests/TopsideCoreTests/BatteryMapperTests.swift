import XCTest
@testable import TopsideCore

final class BatteryMapperTests: XCTestCase {
    private func snap(_ pct: Int?, ac: Bool?, charging: Bool? = nil, charged: Bool? = nil, lpm: Bool = false) -> PowerSnapshot {
        PowerSnapshot(hasBattery: true, percent: pct, isOnACPower: ac, isCharging: charging, isCharged: charged, lowPowerMode: lpm)
    }

    func testDischargingHidesPercentAboveTwenty() {
        let d = BatteryMapper.map(snap(85, ac: false, charging: false))
        XCTAssertEqual(d.status, .discharging); XCTAssertFalse(d.showsPercent); XCTAssertEqual(d.percent, 85)
    }
    func testPercentShownAtOrBelowTwenty() {
        XCTAssertTrue(BatteryMapper.map(snap(20, ac: false)).showsPercent)
        XCTAssertFalse(BatteryMapper.map(snap(21, ac: false)).showsPercent)
        XCTAssertTrue(BatteryMapper.map(snap(10, ac: false)).isCritical)
        XCTAssertFalse(BatteryMapper.map(snap(11, ac: false)).isCritical)
    }
    func testCharging() {
        let d = BatteryMapper.map(snap(50, ac: true, charging: true))
        XCTAssertEqual(d.status, .charging); XCTAssertTrue(d.showsPercent); XCTAssertEqual(d.detail, "50% · Charging")
    }
    func testChargedOnAC() {
        let d = BatteryMapper.map(snap(100, ac: true, charging: false, charged: true))
        XCTAssertEqual(d.status, .charged); XCTAssertFalse(d.showsPercent)
    }
    func testPluggedNotChargingIsDistinctAndNeverClaimsCharging() {
        let d = BatteryMapper.map(snap(80, ac: true, charging: false, charged: false))
        XCTAssertEqual(d.status, .pluggedNotCharging); XCTAssertTrue(d.showsPercent)
        XCTAssertFalse(d.detail.contains("Charging")); XCTAssertTrue(d.detail.contains("not charging"))
    }
    func testUnknownIsNeutralWithNoNumber() {
        for s in [snap(nil, ac: nil), snap(50, ac: nil), snap(nil, ac: true)] {
            let d = BatteryMapper.map(s)
            XCTAssertEqual(d.status, .unknown); XCTAssertNil(d.percent); XCTAssertFalse(d.showsPercent)
            XCTAssertFalse(d.detail.contains(where: \.isNumber))
        }
    }
    func testNoBatteryIsHidden() {
        let d = BatteryMapper.map(PowerSnapshot(hasBattery: false, percent: nil, isOnACPower: nil, isCharging: nil, isCharged: nil, lowPowerMode: false))
        XCTAssertTrue(d.isHidden)
    }
    func testLowPowerModeIsReported() {
        let d = BatteryMapper.map(snap(60, ac: false, lpm: true))
        XCTAssertTrue(d.lowPowerMode); XCTAssertTrue(d.detail.contains("Low Power Mode"))
    }
    func testPercentIsClamped() {
        XCTAssertEqual(BatteryMapper.map(snap(120, ac: false)).percent, 100)
        XCTAssertEqual(BatteryMapper.map(snap(-5, ac: false)).percent, 0)
    }
    func testBatteryWidths() {
        XCTAssertLessThan(BatteryLayout.width(showsPercent: false), BatteryLayout.width(showsPercent: true))
    }
}
