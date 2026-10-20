import AppKit
import SwiftUI
import TopsideCore

/// Never main. It becomes key only after an explicit pin, so hover and ambient
/// presentation cannot steal focus or keystrokes.
final class IslandPanel: NSPanel {
    /// Collapsed/hover states remain non-key. Explicitly pinned content may opt
    /// in so Escape can dismiss it without a global keyboard monitor.
    var allowsKeyInteraction = false
    override var canBecomeKey: Bool { allowsKeyInteraction }
    override var canBecomeMain: Bool { false }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.18 }
}

@MainActor
protocol IslandRootViewDelegate: AnyObject {
    /// Point in pill-local, top-left-origin coordinates; nil = pointer left the pill.
    func rootView(_ view: IslandRootView, pointerMovedTo point: CGPoint?)
    func rootView(_ view: IslandRootView, clickedAt point: CGPoint)
    func rootViewRequestedDismissal(_ view: IslandRootView)
    func rootView(_ view: IslandRootView, moveKeyboardFocusBy delta: Int)
    func rootViewRequestedKeyboardActivation(_ view: IslandRootView)
}

/// Receives hover/click for the whole pill. Flipped so its coordinates match IslandGeometry.
final class IslandRootView: NSView {
    weak var delegate: IslandRootViewDelegate?
    var onPointerMoved: ((CGPoint) -> Void)?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
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

    override func mouseEntered(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointerMoved?(point)
        delegate?.rootView(self, pointerMovedTo: point)
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        onPointerMoved?(point)
        delegate?.rootView(self, pointerMovedTo: point)
    }
    override func mouseExited(with event: NSEvent) { delegate?.rootView(self, pointerMovedTo: nil) }
    override func mouseDown(with event: NSEvent) { delegate?.rootView(self, clickedAt: convert(event.locationInWindow, from: nil)) }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53: // Escape
            delegate?.rootViewRequestedDismissal(self)
        case 48: // Tab / Shift-Tab
            delegate?.rootView(self, moveKeyboardFocusBy: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 123, 126: // Left / Up
            delegate?.rootView(self, moveKeyboardFocusBy: -1)
        case 124, 125: // Right / Down
            delegate?.rootView(self, moveKeyboardFocusBy: 1)
        case 36, 49, 76: // Return / Space / keypad Enter
            delegate?.rootViewRequestedKeyboardActivation(self)
        default:
            return false
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !handleKey(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleKey(event) || super.performKeyEquivalent(with: event)
    }
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
    private var globalPointerMonitor: Any?
    private var visibleSize = CGSize.zero
    private var cornerRadius: CGFloat = 0
    private var earWidth: CGFloat = 0
    private var frameAnimationTimer: Timer?
    private var frameAnimationGeneration = 0

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

        // While the panel ignores a transparent corner, its own tracking area
        // cannot notice the pointer returning to the visible shape. A global
        // mouse-motion monitor re-enables it without Accessibility permission.
        globalPointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.updateMousePassthrough(at: NSEvent.mouseLocation) }
        }
        root.onPointerMoved = { [weak self] in self?.updateMousePassthrough(localPoint: $0) }
    }

    var frame: CGRect { panel.frame }

    func setFrame(_ frame: CGRect, animated: Bool) {
        guard panel.frame != frame else { return }
        frameAnimationTimer?.invalidate()
        frameAnimationTimer = nil
        frameAnimationGeneration += 1

        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true, animate: false)
            updateMousePassthrough(at: NSEvent.mouseLocation)
            return
        }

        // NSWindow's built-in resize animator can throw when a second layout
        // interrupts it. Drive atomic frames ourselves so rapid power/media
        // updates remain interruptible while the surface still moves fluidly.
        let generation = frameAnimationGeneration
        let startFrame = panel.frame
        let startTime = ProcessInfo.processInfo.systemUptime
        // Opening springs slightly past its target; closing is a plain ease-out.
        let growing = frame.width * frame.height >= startFrame.width * startFrame.height
        let duration = IslandMotion.duration(growing: growing)
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceFrameAnimation(generation: generation, from: startFrame, to: frame,
                                            startTime: startTime, duration: duration, growing: growing)
            }
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        frameAnimationTimer = timer
    }

    private func advanceFrameAnimation(generation: Int, from startFrame: CGRect, to targetFrame: CGRect,
                                       startTime: TimeInterval, duration: TimeInterval, growing: Bool) {
        guard frameAnimationGeneration == generation else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - startTime
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = CGFloat(IslandMotion.eased(progress, growing: growing))
        let current = CGRect(
            x: startFrame.minX + (targetFrame.minX - startFrame.minX) * eased,
            y: startFrame.minY + (targetFrame.minY - startFrame.minY) * eased,
            width: startFrame.width + (targetFrame.width - startFrame.width) * eased,
            height: startFrame.height + (targetFrame.height - startFrame.height) * eased
        )
        panel.setFrame(current, display: true, animate: false)
        updateMousePassthrough(at: NSEvent.mouseLocation)
        if progress >= 1 {
            frameAnimationTimer?.invalidate()
            frameAnimationTimer = nil
        }
    }

    func updateInteractiveShape(size: CGSize, cornerRadius: CGFloat, earWidth: CGFloat = 0) {
        visibleSize = size
        self.cornerRadius = cornerRadius
        self.earWidth = earWidth
        updateMousePassthrough(at: NSEvent.mouseLocation)
    }

    func show() {
        updateMousePassthrough(at: NSEvent.mouseLocation)
        panel.orderFrontRegardless()
    }
    func hide() { panel.orderOut(nil) }

    private func updateMousePassthrough(at screenPoint: CGPoint) {
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        updateMousePassthrough(localPoint: rootView.convert(windowPoint, from: nil))
    }

    private func updateMousePassthrough(localPoint: CGPoint) {
        let acceptsPoint = IslandLayout.containsVisibleShape(localPoint, size: visibleSize, cornerRadius: cornerRadius,
                                                         earWidth: earWidth)
        if panel.ignoresMouseEvents == acceptsPoint {
            panel.ignoresMouseEvents = !acceptsPoint
        }
    }

    /// A deliberate click may temporarily make the nonactivating panel key.
    /// Hover and ambient states never call this, so ordinary typing remains in
    /// the foreground application.
    func setKeyboardInteraction(_ enabled: Bool) {
        panel.allowsKeyInteraction = enabled
        if enabled {
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(rootView)
        } else if panel.isKeyWindow {
            panel.resignKey()
        }
    }
}
