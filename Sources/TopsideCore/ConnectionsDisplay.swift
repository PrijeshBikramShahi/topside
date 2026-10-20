import Foundation

// MARK: Wi-Fi (icon only: power, association and signal strength; never the network name)

public struct WiFiSnapshot: Equatable, Sendable {
    public var hasInterface: Bool
    public var powerOn: Bool?
    /// dBm. CoreWLAN reports 0 while not associated.
    public var rssi: Int?
    public init(hasInterface: Bool, powerOn: Bool?, rssi: Int?) {
        self.hasInterface = hasInterface; self.powerOn = powerOn; self.rssi = rssi
    }
    public static let unknown = WiFiSnapshot(hasInterface: false, powerOn: nil, rssi: nil)
}

public enum WiFiState: Equatable, Sendable { case hidden, off, disconnected, connected }

public struct WiFiDisplay: Equatable, Sendable {
    public var state: WiFiState
    /// 0 unless connected; 1...3 otherwise.
    public var level: Int
    public var isHidden: Bool { state == .hidden }
    public var symbol: String {
        switch state {
        case .hidden, .connected: return "wifi"
        case .off: return "wifi.slash"
        case .disconnected: return "wifi.exclamationmark"
        }
    }
    /// For SF Symbols' variable colour; nil for the fixed off/disconnected symbols.
    public var variableValue: Double? { state == .connected ? Double(level) / 3 : nil }
    public var accessibilityLabel: String {
        switch state {
        case .hidden: return ""
        case .off: return "Wi-Fi off"
        case .disconnected: return "Wi-Fi not connected"
        case .connected: return level >= 3 ? "Wi-Fi strong" : level == 2 ? "Wi-Fi good" : "Wi-Fi weak"
        }
    }
}

public enum WiFiMapper {
    public static func map(_ s: WiFiSnapshot) -> WiFiDisplay {
        guard s.hasInterface, let on = s.powerOn else { return WiFiDisplay(state: .hidden, level: 0) }
        guard on else { return WiFiDisplay(state: .off, level: 0) }
        guard let rssi = s.rssi, rssi != 0 else { return WiFiDisplay(state: .disconnected, level: 0) }
        return WiFiDisplay(state: .connected, level: rssi >= -55 ? 3 : rssi >= -67 ? 2 : 1)
    }
}

// MARK: Audio output icon

public enum AudioOutputIcon {
    /// Headphones when something personal is connected, a speaker otherwise. Names are a heuristic:
    /// Core Audio does not say whether a Bluetooth device is headphones or a speaker.
    public static func symbol(name: String, transport: AudioTransport) -> String {
        let n = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { n.contains($0) } }
        let speakerWords = ["speaker", "soundbar", "homepod", "boom", "echo", "sonos", "soundlink", "stereo"]
        let headphoneWords = ["headphone", "headset", "earbud", "earphone", "buds", "beats", "bose qc", "wh-1000", "wf-1000"]
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch transport {
        case .airPlay: return "airplayaudio"
        case .display: return "display"
        case .bluetooth:
            if has(speakerWords) { return "hifispeaker.fill" }
            return "headphones"
        case .usb, .other, .virtual:
            if has(headphoneWords) { return "headphones" }
            return "speaker.wave.2.fill"
        case .builtIn:
            return has(headphoneWords) ? "headphones" : "speaker.wave.2.fill"
        }
    }
}
