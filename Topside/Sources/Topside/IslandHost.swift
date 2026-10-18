import AppKit
import SwiftUI
import TopsideCore

/// Never key, never main: cannot steal focus or keystrokes.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.18 }
}

@MainActor
protocol IslandRootViewDelegate: AnyObject {
    /// Point in pill-local, top-left-origin coordinates; nil = pointer left the pill.
    func rootView(_ view: IslandRootView, pointerMovedTo point: CGPoint?)
    func rootView(_ view: IslandRootView, clickedAt point: CGPoint)
}

/// Receives hover/click for the whole pill. Flipped so its coordinates match IslandGeometry.
final class IslandRootView: NSView {
    weak var delegate: IslandRootViewDelegate?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        // activeAlways: hover works while another app is frontmost.
        let t = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { delegate?.rootView(self, pointerMovedTo: convert(event.locationInWindow, from: nil)) }
    override func mouseMoved(with event: NSEvent) { delegate?.rootView(self, pointerMovedTo: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { delegate?.rootView(self, pointerMovedTo: nil) }
    override func mouseDown(with event: NSEvent) { delegate?.rootView(self, clickedAt: convert(event.locationInWindow, from: nil)) }
}

/// SwiftUI content is display-only; AppKit handles all pointer input so behavior is deterministic.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// ONE panel, sized exactly to the visible pill (no full-width invisible window).
@MainActor
final class IslandHost {
    let panel: IslandPanel
    let rootView: IslandRootView
    private let hosting: PassthroughHostingView<IslandView>

    init(model: IslandModel) {
        let p = IslandPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 36),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar                          // above the menu bar band
        p.hasShadow = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovable = false
        p.animationBehavior = .none
        p.acceptsMouseMovedEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        let root = IslandRootView()
        let host = PassthroughHostingView(rootView: IslandView(model: model))
        host.sizingOptions = []                       // the panel frame is ours, not SwiftUI's
        host.frame = root.bounds
        host.autoresizingMask = [.width, .height]
        root.addSubview(host)
        p.contentView = root

        panel = p
        rootView = root
        hosting = host
    }

    var frame: CGRect { panel.frame }

    func setFrame(_ frame: CGRect, animated: Bool) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true, animate: animated && panel.isVisible)
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}
