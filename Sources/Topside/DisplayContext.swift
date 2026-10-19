import AppKit

/// Immutable snapshot of the display the island is bound to.
/// Invariant: all placement derives from this, never from NSScreen.main in view/event code.
struct DisplayContext: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat
    /// 0 when the menu bar is auto-hidden.
    let menuBarHeight: CGFloat

    @MainActor
    init(screen: NSScreen) {
        id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        frame = screen.frame
        visibleFrame = screen.visibleFrame
        scale = screen.backingScaleFactor
        menuBarHeight = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
    }
}

@MainActor
protocol DisplayProviding {
    func currentContext() -> DisplayContext?
}

/// One island on the active display: the screen that has the menu bar (screens[0]; this is the
/// external display in clamshell mode), falling back to the screen under the pointer.
@MainActor
struct ActiveDisplayProvider: DisplayProviding {
    func currentContext() -> DisplayContext? {
        let screens = NSScreen.screens
        if let menuBarScreen = screens.first { return DisplayContext(screen: menuBarScreen) }
        let mouse = NSEvent.mouseLocation
        if let s = screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main { return DisplayContext(screen: s) }
        return nil
    }
}
