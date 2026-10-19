import Foundation

/// Pure policy for distinguishing native fullscreen from a maximized window when
/// auto-hidden system chrome makes their bounds identical.
public enum FullscreenDecision {
    public static func isFullscreen(
        boundsMatchDisplay: Bool,
        systemChromeIsAmbiguous: Bool,
        accessibilityFullscreen: Bool?,
        secondsSinceSpaceChange: TimeInterval,
        preserveConfirmedFullscreen: Bool = false,
        spaceTransitionCanConfirm: Bool = true
    ) -> Bool {
        guard boundsMatchDisplay else { return false }
        guard systemChromeIsAmbiguous else { return true }
        if let accessibilityFullscreen { return accessibilityFullscreen }
        if preserveConfirmedFullscreen { return true }
        return spaceTransitionCanConfirm && secondsSinceSpaceChange >= 0 && secondsSinceSpaceChange < 1.5
    }
}
