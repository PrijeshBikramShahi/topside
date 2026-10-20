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
        static let notchCorners = "topside.v1.notchCorners"
        static let albumTint = "topside.v1.albumTint"
        static let tintStrength = "topside.v1.tintStrength"
        static let grain = "topside.v1.grain"
        static let grainStrength = "topside.v1.grainStrength"
    }
    static let defaultHeight = 36.0
    static let defaultTopOffset = 0.0
    static let defaultTintStrength = 1.0
    static let defaultGrainStrength = 0.5

    @Published var height: Double { didSet { UserDefaults.standard.set(height, forKey: Key.height); changes.send() } }
    @Published var topOffset: Double { didSet { UserDefaults.standard.set(topOffset, forKey: Key.topOffset); changes.send() } }
    @Published var clockStyle: ClockStyle { didSet { UserDefaults.standard.set(clockStyle.rawValue, forKey: Key.clockStyle); changes.send() } }
    @Published var hideInFullscreen: Bool { didSet { UserDefaults.standard.set(hideInFullscreen, forKey: Key.hideInFullscreen); changes.send() } }
    @Published var globalShortcut: GlobalShortcut { didSet { UserDefaults.standard.set(globalShortcut.rawValue, forKey: Key.globalShortcut); changes.send() } }
    @Published var notchCorners: Bool { didSet { UserDefaults.standard.set(notchCorners, forKey: Key.notchCorners); changes.send() } }
    @Published var albumTint: Bool { didSet { UserDefaults.standard.set(albumTint, forKey: Key.albumTint); changes.send() } }
    @Published var tintStrength: Double { didSet { UserDefaults.standard.set(tintStrength, forKey: Key.tintStrength); changes.send() } }
    @Published var grain: Bool { didSet { UserDefaults.standard.set(grain, forKey: Key.grain); changes.send() } }
    @Published var grainStrength: Double { didSet { UserDefaults.standard.set(grainStrength, forKey: Key.grainStrength); changes.send() } }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginError: String?

    init() {
        let d = UserDefaults.standard
        height = (d.object(forKey: Key.height) as? Double) ?? Preferences.defaultHeight
        topOffset = (d.object(forKey: Key.topOffset) as? Double) ?? Preferences.defaultTopOffset
        clockStyle = ClockStyle(rawValue: d.string(forKey: Key.clockStyle) ?? "") ?? .system
        hideInFullscreen = (d.object(forKey: Key.hideInFullscreen) as? Bool) ?? true
        globalShortcut = GlobalShortcut(rawValue: d.string(forKey: Key.globalShortcut) ?? "") ?? .optionSpace
        notchCorners = (d.object(forKey: Key.notchCorners) as? Bool) ?? true
        albumTint = (d.object(forKey: Key.albumTint) as? Bool) ?? true
        tintStrength = min(max((d.object(forKey: Key.tintStrength) as? Double) ?? Preferences.defaultTintStrength, 0), 1)
        grain = (d.object(forKey: Key.grain) as? Bool) ?? true
        grainStrength = min(max((d.object(forKey: Key.grainStrength) as? Double) ?? Preferences.defaultGrainStrength, 0), 1)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// Width of each concave top-corner flare when notch-style corners are on.
    static let earWidth: CGFloat = 8

    var metrics: IslandMetrics {
        let top = CGFloat(min(max(topOffset, 0), 12))
        // The flare only makes sense when the island is attached to the top edge.
        let ear: CGFloat = (notchCorners && top == 0) ? Preferences.earWidth : 0
        return IslandMetrics(height: CGFloat(min(max(height, 30), 44)), topOffset: top, earWidth: ear)
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
        notchCorners = true
        albumTint = true
        tintStrength = Preferences.defaultTintStrength
        grain = true
        grainStrength = Preferences.defaultGrainStrength
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
