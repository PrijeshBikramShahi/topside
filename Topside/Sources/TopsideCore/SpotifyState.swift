import Foundation

public enum SpotifyAvailability: Equatable, Sendable {
    case notInstalled, closed, needsPermission, permissionDenied, idle, paused, playing, error
}

public struct TrackInfo: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var artworkURL: URL?
    public init(id: String, title: String, artist: String, artworkURL: URL?) {
        self.id = id; self.title = title; self.artist = artist; self.artworkURL = artworkURL
    }
}

public struct SpotifySnapshot: Equatable, Sendable {
    public var availability: SpotifyAvailability
    public var track: TrackInfo?
    public init(_ availability: SpotifyAvailability, track: TrackInfo? = nil) {
        self.availability = availability; self.track = track
    }
}

public enum SpotifyControl: Equatable, Hashable, Sendable {
    case previous, playPause, next, open, connect, openPrivacySettings

    public var buttonTitle: String {
        switch self {
        case .previous: return "Previous"
        case .playPause: return "Play or pause"
        case .next: return "Next"
        case .open: return "Open Spotify"
        case .connect: return "Allow Spotify control"
        case .openPrivacySettings: return "Open Automation settings"
        }
    }
}

public enum CompactIcon: Equatable, Sendable { case play, pause, launch, connect, warning, unavailable }

public struct SpotifyDisplay: Equatable, Sendable {
    public var availability: SpotifyAvailability
    public var title: String
    public var artist: String
    /// One-line text for the hover preview.
    public var detail: String
    /// Second line for the pinned player (artist, or "Paused · artist").
    public var subtitle: String
    public var accessibilityLabel: String
    public var compactIcon: CompactIcon
    /// What the compact button does when clicked; nil = not actionable.
    public var compactControl: SpotifyControl?
    /// Controls shown in the pinned player, in order. Only ones that can work in this state.
    public var controls: [SpotifyControl]
    public var showsArtwork: Bool
    public var isPaused: Bool
    public var artworkURL: URL?

    public init(availability: SpotifyAvailability, title: String, artist: String, detail: String, subtitle: String,
                accessibilityLabel: String, compactIcon: CompactIcon, compactControl: SpotifyControl?,
                controls: [SpotifyControl], showsArtwork: Bool, isPaused: Bool, artworkURL: URL?) {
        self.availability = availability; self.title = title; self.artist = artist; self.detail = detail
        self.subtitle = subtitle; self.accessibilityLabel = accessibilityLabel; self.compactIcon = compactIcon
        self.compactControl = compactControl; self.controls = controls; self.showsArtwork = showsArtwork
        self.isPaused = isPaused; self.artworkURL = artworkURL
    }
}

public enum SpotifyMapper {
    public static func map(_ s: SpotifySnapshot) -> SpotifyDisplay {
        let title = s.track?.title ?? ""
        let artist = s.track?.artist ?? ""
        let line = artist.isEmpty ? title : "\(title) — \(artist)"
        let art = s.track?.artworkURL
        let transport: [SpotifyControl] = [.previous, .playPause, .next, .open]

        func make(_ detail: String, subtitle: String = "", a11y: String? = nil, icon: CompactIcon, compact: SpotifyControl?,
                  controls: [SpotifyControl], artwork: Bool = false, paused: Bool = false, url: URL? = nil) -> SpotifyDisplay {
            SpotifyDisplay(availability: s.availability, title: title, artist: artist, detail: detail, subtitle: subtitle,
                           accessibilityLabel: a11y ?? detail, compactIcon: icon, compactControl: compact,
                           controls: controls, showsArtwork: artwork, isPaused: paused, artworkURL: url)
        }

        switch s.availability {
        case .playing:
            return make(line.isEmpty ? "Playing" : line, subtitle: artist, a11y: "Spotify playing: \(line)",
                        icon: .pause, compact: .playPause, controls: transport, artwork: true, url: art)
        case .paused:
            return make(line.isEmpty ? "Paused" : "Paused · \(line)",
                        subtitle: artist.isEmpty ? "Paused" : "Paused · \(artist)", a11y: "Spotify paused: \(line)",
                        icon: .play, compact: .playPause, controls: transport, artwork: true, paused: true, url: art)
        case .idle:
            return make("Spotify is open, nothing playing", icon: .play, compact: .playPause,
                        controls: [.playPause, .open], artwork: true)
        case .closed:
            return make("Spotify isn't running", a11y: "Spotify is not running. Open Spotify",
                        icon: .launch, compact: .open, controls: [.open])
        case .needsPermission:
            return make("Click to let Topside control Spotify", icon: .connect, compact: .connect, controls: [.connect])
        case .permissionDenied:
            return make("Spotify control is off. Enable it in System Settings", icon: .warning,
                        compact: .openPrivacySettings, controls: [.openPrivacySettings])
        case .notInstalled:
            return make("Spotify isn't installed", icon: .unavailable, compact: nil, controls: [])
        case .error:
            return make("Spotify isn't responding", icon: .warning, compact: nil, controls: [])
        }
    }
}

/// Parses the unit-separator-delimited string produced by the read script in SpotifyBridge.
/// Format: closed | stopped | <state>␟<id>␟<title>␟<artist>␟<artworkURL>
public enum SpotifyParser {
    public static let separator = "\u{1F}"

    public static func parse(_ raw: String) -> SpotifySnapshot {
        let f = raw.components(separatedBy: separator)
        let state = f[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch state {
        case "closed": return SpotifySnapshot(.closed)
        case "stopped": return SpotifySnapshot(.idle)
        case "playing", "paused":
            guard f.count >= 4, !(f[1].isEmpty && f[2].isEmpty) else { return SpotifySnapshot(.error) }
            var url: URL?
            if f.count >= 5, let u = URL(string: f[4]), u.scheme == "https" { url = u }
            let track = TrackInfo(id: f[1], title: f[2], artist: f[3], artworkURL: url)
            return SpotifySnapshot(state == "playing" ? .playing : .paused, track: track)
        default:
            return SpotifySnapshot(.error)
        }
    }
}

/// Small LRU. Keeps artwork memory bounded.
public struct BoundedCache<Key: Hashable, Value> {
    public let capacity: Int
    private var storage: [Key: Value] = [:]
    private var order: [Key] = []   // least recently used first

    public init(capacity: Int) { self.capacity = max(1, capacity) }
    public var count: Int { storage.count }

    public mutating func value(for key: Key) -> Value? {
        guard let v = storage[key] else { return nil }
        touch(key)
        return v
    }

    public mutating func insert(_ value: Value, for key: Key) {
        storage[key] = value
        touch(key)
        while order.count > capacity { storage[order.removeFirst()] = nil }
    }

    public mutating func removeAll() { storage.removeAll(); order.removeAll() }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
