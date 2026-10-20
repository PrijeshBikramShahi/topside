import AppKit
import TopsideCore

/// Reveals a fullscreen-suppressed island after a deliberate top-centre dwell,
/// then hides it again when the pointer leaves the visible island.
@MainActor
final class FullscreenRevealMonitor {
    var displayFrame: (() -> CGRect?)?
    var islandFrame: (() -> CGRect?)?
    var onReveal: (() -> Void)?
    var onHide: (() -> Void)?

    private(set) var isActive = false
    private(set) var isRevealed = false
    private var pointerMonitor: Any?
    private var pointerTimer: Timer?
    private var dwellTask: Task<Void, Never>?
    private var leaveTask: Task<Void, Never>?

    func start() {
        guard pointerMonitor == nil, pointerTimer == nil else { return }
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved(to: NSEvent.mouseLocation) }
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                self.pointerMoved(to: NSEvent.mouseLocation)
            }
        }
        timer.tolerance = 0.02
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        dwellTask?.cancel()
        leaveTask?.cancel()
        dwellTask = nil
        leaveTask = nil
        if !active { isRevealed = false }
        if active { pointerMoved(to: NSEvent.mouseLocation) }
    }

    func pointerMoved(to point: CGPoint) {
        guard isActive else { return }
        if isRevealed {
            let hitFrame = islandFrame?()?.insetBy(dx: -4, dy: -4) ?? .zero
            if hitFrame.contains(point) {
                leaveTask?.cancel()
                leaveTask = nil
            } else if leaveTask == nil {
                leaveTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Timing.fullscreenLeaveGrace * 1_000_000_000))
                    guard let self, !Task.isCancelled, self.isActive, self.isRevealed else { return }
                    let currentFrame = self.islandFrame?()?.insetBy(dx: -4, dy: -4) ?? .zero
                    guard !currentFrame.contains(NSEvent.mouseLocation) else { return }
                    self.isRevealed = false
                    self.leaveTask = nil
                    self.onHide?()
                }
            }
            return
        }

        guard activationZone.contains(point) else {
            dwellTask?.cancel()
            dwellTask = nil
            return
        }
        guard dwellTask == nil else { return }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Timing.fullscreenRevealDwell * 1_000_000_000))
            guard let self, !Task.isCancelled, self.isActive, self.activationZone.contains(NSEvent.mouseLocation) else { return }
            self.dwellTask = nil
            self.isRevealed = true
            self.onReveal?()
        }
    }

    private var activationZone: CGRect {
        guard let display = displayFrame?() else { return .zero }
        let width = min(max(islandFrame?()?.width ?? 184, 184), 284)
        return CGRect(x: display.midX - width / 2, y: display.maxY - 8, width: width, height: 8)
    }
}
