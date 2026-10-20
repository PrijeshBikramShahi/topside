import CoreGraphics
import Foundation

public struct PowerSnapshot: Equatable, Sendable {
    public var hasBattery: Bool
    public var percent: Int?
    public var isOnACPower: Bool?
    public var isCharging: Bool?
    public var isCharged: Bool?
    public var lowPowerMode: Bool

    public init(hasBattery: Bool, percent: Int?, isOnACPower: Bool?, isCharging: Bool?, isCharged: Bool?, lowPowerMode: Bool) {
        self.hasBattery = hasBattery; self.percent = percent; self.isOnACPower = isOnACPower
        self.isCharging = isCharging; self.isCharged = isCharged; self.lowPowerMode = lowPowerMode
    }

    public static let unknown = PowerSnapshot(hasBattery: true, percent: nil, isOnACPower: nil, isCharging: nil, isCharged: nil, lowPowerMode: false)
}

public enum BatteryStatus: Equatable, Sendable { case noBattery, unknown, discharging, charging, pluggedNotCharging, charged }

public struct BatteryDisplay: Equatable, Sendable {
    public var status: BatteryStatus
    public var percent: Int?
    public var showsPercent: Bool
    public var fillFraction: Double
    public var isLow: Bool
    public var isCritical: Bool
    public var lowPowerMode: Bool
    public var detail: String
    public var accessibilityLabel: String
    public var isHidden: Bool { status == .noBattery }

    public init(status: BatteryStatus, percent: Int?, showsPercent: Bool, fillFraction: Double, isLow: Bool, isCritical: Bool,
                lowPowerMode: Bool, detail: String, accessibilityLabel: String) {
        self.status = status; self.percent = percent; self.showsPercent = showsPercent; self.fillFraction = fillFraction
        self.isLow = isLow; self.isCritical = isCritical; self.lowPowerMode = lowPowerMode
        self.detail = detail; self.accessibilityLabel = accessibilityLabel
    }
}

extension BatteryDisplay {
    /// Big number for the pinned view ("62%"), or an em dash when the level is unknown.
    public var headline: String { percent.map { "\($0)%" } ?? "—" }

    /// `detail` without its leading percentage: "On battery", "Charging · Low Power Mode".
    public var statusLine: String {
        guard let percent else { return detail }
        let prefix = "\(percent)% · "
        return detail.hasPrefix(prefix) ? String(detail.dropFirst(prefix.count)) : detail
    }
}

public enum BatteryLayout {
    /// Glyph is 24pt wide; percent text adds 40pt (8pt gap plus the text).
    public static func width(showsPercent: Bool) -> CGFloat { showsPercent ? 64 : 24 }
}

public enum BatteryMapper {
    public static func map(_ s: PowerSnapshot) -> BatteryDisplay {
        guard s.hasBattery else {
            return BatteryDisplay(status: .noBattery, percent: nil, showsPercent: false, fillFraction: 0, isLow: false,
                                  isCritical: false, lowPowerMode: false, detail: "No battery", accessibilityLabel: "No battery")
        }
        guard let raw = s.percent, let onAC = s.isOnACPower else {
            // Unknown is neutral: never a made-up number.
            return BatteryDisplay(status: .unknown, percent: nil, showsPercent: false, fillFraction: 0, isLow: false,
                                  isCritical: false, lowPowerMode: s.lowPowerMode, detail: "Battery status unavailable",
                                  accessibilityLabel: "Battery status unavailable")
        }
        let pct = min(max(raw, 0), 100)
        let status: BatteryStatus
        if s.isCharging == true { status = .charging }
        else if onAC { status = (s.isCharged == true || pct >= 100) ? .charged : .pluggedNotCharging }
        else { status = .discharging }

        let discharging = status == .discharging
        let isLow = discharging && pct <= 20
        let isCritical = discharging && pct <= 10
        // Percentage shown when charging, plugged-not-charging, or at/below 20%.
        let showsPercent = status == .charging || status == .pluggedNotCharging || isLow

        var detail: String
        switch status {
        case .charging: detail = "\(pct)% · Charging"
        case .charged: detail = "\(pct)% · Charged"
        case .pluggedNotCharging: detail = "\(pct)% · Plugged in, not charging"
        default: detail = "\(pct)% · On battery"
        }
        if s.lowPowerMode { detail += " · Low Power Mode" }

        return BatteryDisplay(status: status, percent: pct, showsPercent: showsPercent, fillFraction: Double(pct) / 100,
                              isLow: isLow, isCritical: isCritical, lowPowerMode: s.lowPowerMode,
                              detail: detail, accessibilityLabel: "Battery \(detail)")
    }
}
