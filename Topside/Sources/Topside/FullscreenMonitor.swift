import AppKit

/// Heuristic (no permissions): the frontmost app owns a normal-layer window exactly the size of the
/// island's display. A maximized window is shorter (menu bar / Dock). Re-checks on Space/app changes.
/// Known false positive: menu bar AND Dock both auto-hidden with a zoomed window.
@MainActor
final class FullscreenMonitor: NSObject {
    var displayFrame: (() -> CGRect?)?
    var onChange: ((Bool) -> Void)?
    var enabled = true { didSet { recheck() } }
    private(set) var isFullscreen = false

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(trigger), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(trigger), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        recheck()
    }

    @objc private func trigger() {
        recheck()
        Task {   // fullscreen transitions settle a moment after the notification
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.recheck()
        }
    }

    func recheck() {
        let result = enabled && frontmostAppHasFullscreenWindow()
        guard result != isFullscreen else { return }
        isFullscreen = result
        Log.info("fullscreenCheck result=\(result)")
        onChange?(result)
    }

    private func frontmostAppHasFullscreenWindow() -> Bool {
        guard let frame = displayFrame?(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        // CG window space has a top-left origin anchored to the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let target = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        for w in windows {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if abs(rect.minX - target.minX) < 1, abs(rect.minY - target.minY) < 1,
               abs(rect.width - target.width) < 1, abs(rect.height - target.height) < 1 { return true }
        }
        return false
    }
}
