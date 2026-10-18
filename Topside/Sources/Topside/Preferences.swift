import Combine
import CoreGraphics
import Foundation
import TopsideCore

/// Few keys, versioned names.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    let changes = PassthroughSubject<Void, Never>()

    private enum Key {
        static let height = "topside.v1.height"
        static let topOffset = "topside.v1.topOffset"
        static let clockStyle = "topside.v1.clockStyle"
        static let hideInFullscreen = "topside.v1.hideInFullscreen"
    }
    static let defaultHeight = 36.0
    static let defaultTopOffset = 0.0

    @Published var height: Double { didSet { UserDefaults.standard.set(height, forKey: Key.height); changes.send() } }
    @Published var topOffset: Double { didSet { UserDefaults.standard.set(topOffset, forKey: Key.topOffset); changes.send() } }
    @Published var clockStyle: ClockStyle { didSet { UserDefaults.standard.set(clockStyle.rawValue, forKey: Key.clockStyle); changes.send() } }
    @Published var hideInFullscreen: Bool { didSet { UserDefaults.standard.set(hideInFullscreen, forKey: Key.hideInFullscreen); changes.send() } }

    init() {
        let d = UserDefaults.standard
        height = (d.object(forKey: Key.height) as? Double) ?? Preferences.defaultHeight
        topOffset = (d.object(forKey: Key.topOffset) as? Double) ?? Preferences.defaultTopOffset
        clockStyle = ClockStyle(rawValue: d.string(forKey: Key.clockStyle) ?? "") ?? .system
        hideInFullscreen = (d.object(forKey: Key.hideInFullscreen) as? Bool) ?? true
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
    }
}
