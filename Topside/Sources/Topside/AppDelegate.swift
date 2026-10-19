import AppKit
import Combine

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // no Dock icon; the status item is the way back in
        app.run()
    }

    private var island: IslandController?
    private var status: StatusItemController?
    private let settings = SettingsWindowController()
    private let hotKey = GlobalHotKeyService()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single instance: if one is already running, bring up its Settings and exit.
        if let id = Bundle.main.bundleIdentifier {
            let me = ProcessInfo.processInfo.processIdentifier
            if NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != me }) {
                NSApp.terminate(nil)
                return
            }
        }
        Log.info("---- launch ---- \(ProcessInfo.processInfo.operatingSystemVersionString) bundle=\(Bundle.main.bundleIdentifier ?? "none")")

        let island = IslandController()
        self.island = island

        let status = StatusItemController()
        status.isIslandHidden = { [weak island] in island?.isUserHidden ?? false }
        status.onToggleHidden = { [weak island] in island?.toggleUserHidden() }
        status.onSettings = { [weak self] in self?.settings.show() }
        status.onResetPlacement = { Preferences.shared.resetPlacement() }
        status.onMenuTracking = { [weak island] in island?.setOwnMenuTracking($0) }
        status.install()
        self.status = status

        island.start()

        hotKey.onPress = { [weak island] in island?.toggleUserHidden() }
        hotKey.update(Preferences.shared.globalShortcut)
        Preferences.shared.$globalShortcut.dropFirst().sink { [weak self] shortcut in
            self?.hotKey.update(shortcut)
        }.store(in: &cancellables)
    }

    /// Relaunching an already-running app lands here: Settings is the always-available way back in.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return true
    }
}
