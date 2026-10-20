import Foundation

/// A playback position sampled at one instant. The UI extrapolates from the sample while the
/// track is playing, so Spotify only has to be asked occasionally.
public struct PlaybackProgress: Equatable, Sendable {
    public var duration: TimeInterval
    public var position: TimeInterval

    public init(duration: TimeInterval, position: TimeInterval) {
        let d = max(0, duration)
        self.duration = d
        self.position = min(max(0, position), d)
    }

    /// Position `elapsed` seconds after the sample was taken. Clamped to the track length.
    public func position(afterSampleBy elapsed: TimeInterval, isPlaying: Bool) -> TimeInterval {
        guard isPlaying else { return position }
        return min(max(0, position + max(0, elapsed)), duration)
    }

    /// 0...1
    public func fraction(afterSampleBy elapsed: TimeInterval, isPlaying: Bool) -> Double {
        guard duration > 0 else { return 0 }
        return position(afterSampleBy: elapsed, isPlaying: isPlaying) / duration
    }

    /// "3:07", or "1:02:03" for tracks of an hour or more.
    public static func label(for seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(m):\(two(s))"
    }
}
