import AppKit
import CoreGraphics

/// Watches public Core Graphics window metadata for tracked menus. AppKit menu
/// windows use the popup-menu level, whether they belong to Topside, another
/// application, or a menu-bar extra. No Accessibility or Screen Recording
/// permission is required for the layer/owner metadata used here.
@MainActor
final class MenuTrackingMonitor {
    var onChange: ((Bool) -> Void)?
    var islandFrame: (() -> CGRect?)?
    private(set) var isTracking = false
    private var timer: Timer?
    private let popupLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))

    func start() {
        guard timer == nil else { return }
        recheck()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.recheck() }
        }
        timer.tolerance = 0.025
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func recheck() {
        publish(overlappingMenuWindowIsVisible())
    }

    /// Menu windows are created asynchronously after the click. The polling
    /// timer observes their actual bounds, so a menu-bar click alone must not
    /// hide the island.
    func noteGlobalMouseDown(at point: CGPoint) {
        _ = point
        recheck()
    }

    func setOwnMenuTracking(_ tracking: Bool) {
        _ = tracking
        recheck()
    }

    private func publish(_ tracking: Bool) {
        guard tracking != isTracking else { return }
        isTracking = tracking
        Log.info("menuTracking=\(tracking)")
        onChange?(tracking)
    }

    private func overlappingMenuWindowIsVisible() -> Bool {
        guard let island = islandFrame?(), !island.isEmpty else { return false }
        let protectedFrame = island.insetBy(dx: -2, dy: -2)
        guard let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return false }
        return windows.contains { window in
            let level = window[kCGWindowLayer as String] as? Int ?? -1
            guard (popupLevel...(popupLevel + 2)).contains(level),
                  (window[kCGWindowOwnerPID as String] as? Int32) == frontmostPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { return false }
            // Tiny windows at these levels are generally tooltips or transient
            // labels rather than menus. Restricting the owner to the frontmost
            // app also excludes power/notification overlays during unplug.
            return rect.width >= 80 && rect.height >= 20
                && appKitScreenRect(fromQuartzScreenRect: rect).intersects(protectedFrame)
        }
    }

    /// Quartz window-list rectangles use a top-left global origin while AppKit
    /// window rectangles use the primary display's bottom-left origin.
    private func appKitScreenRect(fromQuartzScreenRect rect: CGRect) -> CGRect {
        let primaryMaxY = NSScreen.screens.first {
            $0.frame.minX == 0 && $0.frame.minY == 0
        }?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: primaryMaxY - rect.maxY,
                      width: rect.width, height: rect.height)
    }
}
