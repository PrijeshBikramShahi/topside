import Foundation

public enum AnnouncementTone: Equatable, Sendable { case neutral, warning, critical }

/// What the island says about a power change. Pure data; the controller decides when to show it.
public enum PowerAnnouncement: Equatable, Sendable {
    case charging(percent: Int?)
    case pluggedIn(percent: Int?)
    case charged
    case onBattery(percent: Int?)
    case low(percent: Int)
    case critical(percent: Int)

    public var message: String {
        func suffix(_ p: Int?) -> String { p.map { " · \($0)%" } ?? "" }
        switch self {
        case .charging(let p): return "Charging" + suffix(p)
        case .pluggedIn(let p): return "Plugged in" + suffix(p)
        case .charged: return "Battery charged"
        case .onBattery(let p): return "Running on battery" + suffix(p)
        case .low(let p): return "Battery low · \(p)%"
        case .critical(let p): return "Battery critical · \(p)%"
        }
    }

    public var tone: AnnouncementTone {
        switch self {
        case .low: return .warning
        case .critical: return .critical
        default: return .neutral
        }
    }
}

public enum PowerEvents {
    static func isPlugged(_ s: BatteryStatus) -> Bool {
        s == .charging || s == .charged || s == .pluggedNotCharging
    }

    /// A real plug/unplug/full event. Moves between the two "plugged in" states
    /// (charging <-> plugged, not charging) are silent: Optimized Battery Charging can flip
    /// between them near 80% and that must never pop the island open.
    public static func announcement(from old: BatteryStatus, to new: BatteryDisplay) -> PowerAnnouncement? {
        guard old != .unknown, old != .noBattery, old != new.status else { return nil }
        switch new.status {
        case .noBattery, .unknown:
            return nil
        case .charging:
            return isPlugged(old) ? nil : .charging(percent: new.percent)
        case .pluggedNotCharging:
            return isPlugged(old) ? nil : .pluggedIn(percent: new.percent)
        case .charged:
            return old == .charged ? nil : .charged
        case .discharging:
            return isPlugged(old) ? .onBattery(percent: new.percent) : nil
        }
    }

    /// Fires once when a discharging battery falls through 20% or 10%. Never on plug-in, launch or wake
    /// (those have no discharging `old`), and never when the level rises.
    public static func thresholdCrossing(from old: BatteryDisplay, to new: BatteryDisplay) -> PowerAnnouncement? {
        guard old.status == .discharging, new.status == .discharging,
              let before = old.percent, let after = new.percent, after < before else { return nil }
        if before > 10, after <= 10 { return .critical(percent: after) }
        if before > 20, after <= 20 { return .low(percent: after) }
        return nil
    }
}

/// Remembers the last status the user was told about, so a flapping reading that settles back on it says nothing.
public struct PowerAnnouncer: Sendable {
    private var announced: BatteryStatus?
    public init() {}

    /// Call after the status has stopped changing. The first resolved reading is only a baseline.
    /// While `quiet` (just woke, just unlocked) the baseline moves but nothing is announced.
    public mutating func settle(_ display: BatteryDisplay, quiet: Bool) -> PowerAnnouncement? {
        guard display.status != .unknown else { return nil }
        defer { announced = display.status }
        guard let old = announced, !quiet else { return nil }
        return PowerEvents.announcement(from: old, to: display)
    }
}

public enum AudioTransport: Equatable, Sendable { case builtIn, bluetooth, usb, airPlay, display, virtual, other }

public enum AudioRoutePolicy {
    /// Say something only when the user plausibly just connected something: Bluetooth, USB or AirPlay.
    /// Falling back to the speakers, monitor audio appearing on hot-plug, and virtual devices stay silent.
    public static func shouldAnnounce(to transport: AudioTransport) -> Bool {
        switch transport {
        case .bluetooth, .usb, .airPlay: return true
        case .builtIn, .display, .virtual, .other: return false
        }
    }
}

/// A short "don't announce" period after wake or unlock, when queued hardware changes arrive late.
public struct QuietWindow: Sendable {
    private var until: Date?
    public init() {}
    public mutating func begin(for duration: TimeInterval, now: Date = Date()) {
        let end = now.addingTimeInterval(duration)
        if until.map({ end > $0 }) ?? true { until = end }
    }
    public func isQuiet(now: Date = Date()) -> Bool { until.map { now < $0 } ?? false }
}
