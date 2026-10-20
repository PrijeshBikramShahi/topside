import XCTest
@testable import TopsideCore

final class HardwareEventsTests: XCTestCase {
    private func display(_ pct: Int, onAC: Bool, charging: Bool = false, charged: Bool = false) -> BatteryDisplay {
        BatteryMapper.map(PowerSnapshot(hasBattery: true, percent: pct, isOnACPower: onAC, isCharging: charging,
                                        isCharged: charged, lowPowerMode: false))
    }

    func testPlugInAndUnplugAnnounce() {
        XCTAssertEqual(PowerEvents.announcement(from: .discharging, to: display(60, onAC: true, charging: true)), .charging(percent: 60))
        XCTAssertEqual(PowerEvents.announcement(from: .charging, to: display(60, onAC: false)), .onBattery(percent: 60))
        XCTAssertEqual(PowerEvents.announcement(from: .discharging, to: display(80, onAC: true)), .pluggedIn(percent: 80))
    }

    func testReachingFullAnnouncesOnce() {
        let full = display(100, onAC: true, charged: true)
        XCTAssertEqual(PowerEvents.announcement(from: .charging, to: full), .charged)
        XCTAssertNil(PowerEvents.announcement(from: .charged, to: full))
    }

    func testMovingBetweenPluggedStatesIsSilent() {
        XCTAssertNil(PowerEvents.announcement(from: .charging, to: display(80, onAC: true)))
        XCTAssertNil(PowerEvents.announcement(from: .pluggedNotCharging, to: display(80, onAC: true, charging: true)))
    }

    func testUnknownBaselineIsSilent() {
        XCTAssertNil(PowerEvents.announcement(from: .unknown, to: display(60, onAC: true, charging: true)))
        XCTAssertNil(PowerEvents.announcement(from: .noBattery, to: display(60, onAC: false)))
    }

    func testThresholdFiresOnceWhenDischargingCrossesDown() {
        XCTAssertEqual(PowerEvents.thresholdCrossing(from: display(21, onAC: false), to: display(20, onAC: false)), .low(percent: 20))
        XCTAssertNil(PowerEvents.thresholdCrossing(from: display(20, onAC: false), to: display(19, onAC: false)))
        XCTAssertEqual(PowerEvents.thresholdCrossing(from: display(11, onAC: false), to: display(10, onAC: false)), .critical(percent: 10))
    }

    func testBigDropReportsOnlyTheWorseThreshold() {
        XCTAssertEqual(PowerEvents.thresholdCrossing(from: display(25, onAC: false), to: display(9, onAC: false)), .critical(percent: 9))
    }

    func testThresholdIgnoresRisingLevelsAndChargers() {
        XCTAssertNil(PowerEvents.thresholdCrossing(from: display(19, onAC: false), to: display(21, onAC: false)))
        XCTAssertNil(PowerEvents.thresholdCrossing(from: display(21, onAC: true, charging: true), to: display(20, onAC: true, charging: true)))
        XCTAssertNil(PowerEvents.thresholdCrossing(from: display(20, onAC: false), to: display(15, onAC: true, charging: true)))
    }

    func testToneAndMessages() {
        XCTAssertEqual(PowerAnnouncement.low(percent: 20).tone, .warning)
        XCTAssertEqual(PowerAnnouncement.critical(percent: 10).tone, .critical)
        XCTAssertEqual(PowerAnnouncement.charging(percent: 62).message, "Charging · 62%")
        XCTAssertEqual(PowerAnnouncement.onBattery(percent: nil).message, "Running on battery")
    }

    // MARK: Announcer

    func testFirstReadingIsOnlyABaseline() {
        var a = PowerAnnouncer()
        XCTAssertNil(a.settle(display(60, onAC: true, charging: true), quiet: false))
        XCTAssertEqual(a.settle(display(60, onAC: false), quiet: false), .onBattery(percent: 60))
    }

    func testFlappingThatSettlesBackSaysNothing() {
        var a = PowerAnnouncer()
        _ = a.settle(display(60, onAC: false), quiet: false)
        XCTAssertNil(a.settle(display(60, onAC: false), quiet: false))
    }

    func testChargingAndPluggedFlipAreSilentAfterTheFirstAnnouncement() {
        var a = PowerAnnouncer()
        _ = a.settle(display(79, onAC: false), quiet: false)
        XCTAssertEqual(a.settle(display(79, onAC: true, charging: true), quiet: false), .charging(percent: 79))
        XCTAssertNil(a.settle(display(80, onAC: true), quiet: false))
        XCTAssertNil(a.settle(display(80, onAC: true, charging: true), quiet: false))
    }

    func testQuietWindowMovesBaselineWithoutAnnouncing() {
        var a = PowerAnnouncer()
        _ = a.settle(display(60, onAC: true, charging: true), quiet: false)
        XCTAssertNil(a.settle(display(60, onAC: false), quiet: true))          // unplugged while asleep
        XCTAssertNil(a.settle(display(60, onAC: false), quiet: false))         // and not announced later either
    }

    func testUnknownReadingKeepsLastBaseline() {
        var a = PowerAnnouncer()
        _ = a.settle(display(60, onAC: false), quiet: false)
        XCTAssertNil(a.settle(BatteryMapper.map(.unknown), quiet: false))
        XCTAssertNil(a.settle(display(60, onAC: false), quiet: false))
    }

    // MARK: Audio and quiet window

    func testOnlyDeliberateConnectionsAnnounceAudio() {
        XCTAssertTrue(AudioRoutePolicy.shouldAnnounce(to: .bluetooth))
        XCTAssertTrue(AudioRoutePolicy.shouldAnnounce(to: .usb))
        XCTAssertTrue(AudioRoutePolicy.shouldAnnounce(to: .airPlay))
        for t: AudioTransport in [.builtIn, .display, .virtual, .other] { XCTAssertFalse(AudioRoutePolicy.shouldAnnounce(to: t)) }
    }

    func testQuietWindowExpiresAndOnlyExtends() {
        var w = QuietWindow()
        let t0 = Date(timeIntervalSince1970: 1000)
        XCTAssertFalse(w.isQuiet(now: t0))
        w.begin(for: 2.5, now: t0)
        XCTAssertTrue(w.isQuiet(now: t0.addingTimeInterval(2.4)))
        XCTAssertFalse(w.isQuiet(now: t0.addingTimeInterval(2.6)))
        w.begin(for: 5, now: t0); w.begin(for: 1, now: t0)
        XCTAssertTrue(w.isQuiet(now: t0.addingTimeInterval(4.9)))
    }

    func testHoverIsQuickerThanBefore() {
        XCTAssertLessThan(Timing.hoverDwell, 0.12)
        XCTAssertLessThan(IslandMotion.duration(growing: false), IslandMotion.duration(growing: true))
    }
}

final class ConnectionsDisplayTests: XCTestCase {
    func testWifiStates() {
        XCTAssertTrue(WiFiMapper.map(.unknown).isHidden)
        XCTAssertTrue(WiFiMapper.map(WiFiSnapshot(hasInterface: false, powerOn: true, rssi: -50)).isHidden)
        XCTAssertEqual(WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: false, rssi: 0)).state, .off)
        XCTAssertEqual(WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: true, rssi: 0)).state, .disconnected)
        XCTAssertEqual(WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: true, rssi: nil)).state, .disconnected)
    }

    func testWifiSignalLevels() {
        func level(_ rssi: Int) -> Int { WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: true, rssi: rssi)).level }
        XCTAssertEqual(level(-40), 3); XCTAssertEqual(level(-55), 3)
        XCTAssertEqual(level(-56), 2); XCTAssertEqual(level(-67), 2)
        XCTAssertEqual(level(-68), 1); XCTAssertEqual(level(-90), 1)
    }

    func testWifiSymbols() {
        let on = WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: true, rssi: -60))
        XCTAssertEqual(on.symbol, "wifi"); XCTAssertEqual(on.variableValue ?? 0, 2.0 / 3.0, accuracy: 1e-9)
        let off = WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: false, rssi: 0))
        XCTAssertEqual(off.symbol, "wifi.slash"); XCTAssertNil(off.variableValue)
        XCTAssertEqual(WiFiMapper.map(WiFiSnapshot(hasInterface: true, powerOn: true, rssi: 0)).symbol, "wifi.exclamationmark")
    }

    func testOutputIcons() {
        XCTAssertEqual(AudioOutputIcon.symbol(name: "MacBook Pro Speakers", transport: .builtIn), "speaker.wave.2.fill")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "Headphones", transport: .builtIn), "headphones")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "Sam’s AirPods Pro", transport: .bluetooth), "airpodspro")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "AirPods Max", transport: .bluetooth), "airpodsmax")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "AirPods (3rd generation)", transport: .bluetooth), "airpods")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "WH-1000XM5", transport: .bluetooth), "headphones")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "JBL Flip Speaker", transport: .bluetooth), "hifispeaker.fill")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "Living Room", transport: .airPlay), "airplayaudio")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "LG Ultrafine", transport: .display), "display")
        XCTAssertEqual(AudioOutputIcon.symbol(name: "USB Audio DAC", transport: .usb), "speaker.wave.2.fill")
    }
}
