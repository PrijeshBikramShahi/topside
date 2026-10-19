import AppKit

/// Recovery route: Quit and Settings are always reachable from here.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let hideItem = NSMenuItem(title: "Hide Island", action: nil, keyEquivalent: "")

    var isIslandHidden: () -> Bool = { false }
    var onToggleHidden: () -> Void = {}
    var onSettings: () -> Void = {}
    var onResetPlacement: () -> Void = {}
    var onMenuTracking: (Bool) -> Void = { _ in }

    func install() {
        if let button = item.button {
            if let image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Topside") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "T"
            }
        }
        let menu = NSMenu()
        menu.delegate = self

        let title = NSMenuItem(title: "Topside", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        hideItem.action = #selector(toggleHidden)
        hideItem.target = self
        menu.addItem(hideItem)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let reset = NSMenuItem(title: "Reset Island Placement", action: #selector(resetPlacement), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Topside", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        hideItem.title = isIslandHidden() ? "Show Island" : "Hide Island"
    }

    func menuWillOpen(_ menu: NSMenu) { onMenuTracking(true) }
    func menuDidClose(_ menu: NSMenu) { onMenuTracking(false) }

    @objc private func toggleHidden() { onToggleHidden() }
    @objc private func openSettings() { onSettings() }
    @objc private func resetPlacement() { onResetPlacement() }
    @objc private func quit() { NSApp.terminate(nil) }
}
