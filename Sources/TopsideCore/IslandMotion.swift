import Foundation

/// Easing for the panel-frame animation. Growing gets a small overshoot so the island feels like
/// it springs open; shrinking is a plain ease-out so it settles without bouncing.
public enum IslandMotion {
    public static let growDuration: TimeInterval = 0.20
    public static let shrinkDuration: TimeInterval = 0.20
    /// ~5% overshoot at the peak (about 3 pt on a 54 pt width change).
    static let overshoot = 1.2

    public static func duration(growing: Bool) -> TimeInterval {
        growing ? growDuration : shrinkDuration
    }

    /// Maps linear progress 0...1 to eased progress. 0 -> 0 and 1 -> 1 exactly.
    public static func eased(_ t: Double, growing: Bool) -> Double {
        let x = min(max(t, 0), 1)
        if growing {
            let u = x - 1
            return 1 + (overshoot + 1) * u * u * u + overshoot * u * u
        }
        let inv = 1 - x
        return 1 - inv * inv * inv
    }
}
