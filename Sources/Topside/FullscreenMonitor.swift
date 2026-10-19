import AppKit
import ApplicationServices
import TopsideCore

/// A fullscreen candidate owns a normal-layer window exactly the size of the island's display.
/// When menu bar and Dock geometry make a zoomed window indistinguishable, a non-prompting AX
/// fullscreen read or a real Space transition is required instead of guessing from bounds alone.
@MainActor
final class FullscreenMonitor: NSObject {
    var displayContext: (() -> DisplayContext?)?
    var onChange: ((Bool) -> Void)?
    var enabled = true { didSet { recheck() } }
    private(set) var isFullscreen = false
    private var lastSpaceChange = Date.distantPast
    private var spaceGeneration = 0
    private var confirmedPID: pid_t?
    private var confirmedSpaceGeneration: Int?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(spaceChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(applicationChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        recheck()
        Task { [weak self] in
            // Accessory apps can briefly appear frontmost during their own launch.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.recheck()
        }
    }

    @objc private func spaceChanged() {
        spaceGeneration += 1
        lastSpaceChange = Date()
        triggerSettledCheck()
    }

    @objc private func applicationChanged() { triggerSettledCheck() }

    private func triggerSettledCheck() {
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
        if !result {
            confirmedPID = nil
            confirmedSpaceGeneration = nil
        }
        Log.info("fullscreenCheck result=\(result)")
        onChange?(result)
    }

    private func frontmostAppHasFullscreenWindow() -> Bool {
        guard let context = displayContext?(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let frame = context.frame
        // CG window space has a top-left origin anchored to the primary display.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let target = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        for w in windows {
            guard (w[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if abs(rect.minX - target.minX) < 1, abs(rect.minY - target.minY) < 1,
               abs(rect.width - target.width) < 1, abs(rect.height - target.height) < 1 {
                let chromeIsAmbiguous = context.menuBarHeight < 1 && rectsMatch(context.visibleFrame, context.frame)
                let axFullscreen = chromeIsAmbiguous ? accessibilityFullscreen(pid: app.processIdentifier) : nil
                let sameConfirmedApp = confirmedPID == app.processIdentifier
                let sameConfirmedSpace = sameConfirmedApp && confirmedSpaceGeneration == spaceGeneration
                let transitionedAwayFromSameApp = sameConfirmedApp && confirmedSpaceGeneration != spaceGeneration
                // Entering/switching to a native fullscreen Space emits this notification;
                // merely zooming a window in place does not.
                let result = FullscreenDecision.isFullscreen(
                    boundsMatchDisplay: true,
                    systemChromeIsAmbiguous: chromeIsAmbiguous,
                    accessibilityFullscreen: axFullscreen,
                    secondsSinceSpaceChange: Date().timeIntervalSince(lastSpaceChange),
                    preserveConfirmedFullscreen: sameConfirmedSpace,
                    spaceTransitionCanConfirm: !transitionedAwayFromSameApp
                )
                if result {
                    confirmedPID = app.processIdentifier
                    confirmedSpaceGeneration = spaceGeneration
                }
                return result
            }
        }
        return false
    }

    private func rectsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 1 && abs(lhs.minY - rhs.minY) < 1 &&
        abs(lhs.width - rhs.width) < 1 && abs(lhs.height - rhs.height) < 1
    }

    /// Reads AXFullScreen only when already available; this never requests or prompts
    /// for Accessibility permission.
    private func accessibilityFullscreen(pid: pid_t) -> Bool? {
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, "AXFullScreen" as CFString, &value) == .success,
              let number = value as? NSNumber else { return nil }
        return number.boolValue
    }
}
