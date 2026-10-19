import Combine
import CoreGraphics
import Foundation
import ServiceManagement
import TopsideCore

/// Few keys, versioned names.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()
    let changes = PassthroughSubject<Void, Never>()

    private enum Key {
        static let height = "topside.v1.height"
        static let topOffset = "topside.v1.topOffset"
        static let clockStyle = "topside.v1.clockStyle"
        static let hideInFullscreen = "topside.v1.hideInFullscreen"
        static let globalShortcut = "topside.v1.globalShortcut"
    }
    static let defaultHeight = 36.0
    static let defaultTopOffset = 0.0

    @Published var height: Double { didSet { UserDefaults.standard.set(height, forKey: Key.height); changes.send() } }
    @Published var topOffset: Double { didSet { UserDefaults.standard.set(topOffset, forKey: Key.topOffset); changes.send() } }
    @Published var clockStyle: ClockStyle { didSet { UserDefaults.standard.set(clockStyle.rawValue, forKey: Key.clockStyle); changes.send() } }
    @Published var hideInFullscreen: Bool { didSet { UserDefaults.standard.set(hideInFullscreen, forKey: Key.hideInFullscreen); changes.send() } }
    @Published var globalShortcut: GlobalShortcut { didSet { UserDefaults.standard.set(globalShortcut.rawValue, forKey: Key.globalShortcut); changes.send() } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?

    init() {
        let d = UserDefaults.standard
        height = (d.object(forKey: Key.height) as? Double) ?? Preferences.defaultHeight
        topOffset = (d.object(forKey: Key.topOffset) as? Double) ?? Preferences.defaultTopOffset
        clockStyle = ClockStyle(rawValue: d.string(forKey: Key.clockStyle) ?? "") ?? .system
        hideInFullscreen = (d.object(forKey: Key.hideInFullscreen) as? Bool) ?? true
        globalShortcut = GlobalShortcut(rawValue: d.string(forKey: Key.globalShortcut) ?? "") ?? .optionSpace
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var metrics: IslandMetrics {
        IslandMetrics(height: CGFloat(min(max(height, 30), 44)), topOffset: CGFloat(min(max(topOffset, 0), 12)))
    }

    func resetPlacement() {
        height = Preferences.defaultHeight
        topOffset = Preferences.defaultTopOffset
    }

    func resetToDefaults() {
        height = Preferences.defaultHeight
        topOffset = Preferences.defaultTopOffset
        clockStyle = .system
        hideInFullscreen = true
        globalShortcut = .optionSpace
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
            Log.info("launchAtLogin failed enabled=\(enabled) error=\(error.localizedDescription)")
        }
    }
}
