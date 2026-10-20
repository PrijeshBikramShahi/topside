import Foundation

/// Named constants, tuned by feel (not user settings yet).
public enum Timing {
    public static let hoverDwell: TimeInterval = 0.080
    public static let leaveGrace: TimeInterval = 0.400
    public static let fullscreenRevealDwell: TimeInterval = 0.500
    public static let fullscreenLeaveGrace: TimeInterval = 0.200
    public static let transientDuration: TimeInterval = 1.8         // reserved: transient cues (Phase 3)
    /// A plug/unplug must hold this long before it is announced, so a flickering reading says nothing.
    public static let powerSettle: TimeInterval = 0.8
    /// After wake or unlock, hardware changes that queued up while away are not announced.
    public static let wakeQuiet: TimeInterval = 2.5
}
