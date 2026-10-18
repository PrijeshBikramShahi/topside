import Foundation

/// Named constants, tuned by feel (not user settings yet).
public enum Timing {
    public static let hoverDwell: TimeInterval = 0.300
    public static let leaveGrace: TimeInterval = 0.400
    public static let fullscreenRevealDwell: TimeInterval = 0.500   // reserved: fullscreen reveal (later)
    public static let transientDuration: TimeInterval = 1.8         // reserved: transient cues (Phase 3)
}
