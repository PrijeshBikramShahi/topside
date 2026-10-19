import AppKit
import TopsideCore

/// Event-driven: Spotify's playback notification and app launch/quit trigger a (coalesced) read.
/// A slow safety poll runs only while Spotify is running, to heal any missed event or a permission change.
@MainActor
final class SpotifyService: NSObject {
    var onChange: ((SpotifySnapshot) -> Void)?

    private let queue = DispatchQueue(label: "app.topside.spotify", qos: .userInitiated)   // serial; Apple Events live here
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var safetyTimer: Timer?
    private var lastAvailability: SpotifyAvailability?
    private var eventCount = 0
    private var retention = SpotifyStateRetention()

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged), name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.safetyPoll() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
        refresh()
    }

    @objc private func playbackChanged(_ note: Notification) {
        eventCount += 1
        if eventCount == 1 { Log.info("spotify: first playback notification received (event-driven path works)") }
        refresh(after: 0.1)
    }

    @objc private func appLaunched(_ note: Notification) {
        guard isSpotify(note) else { return }
        refresh(after: 1.5)   // give Spotify a moment to become scriptable
    }

    @objc private func appTerminated(_ note: Notification) {
        guard isSpotify(note) else { return }
        refresh()
    }

    private func isSpotify(_ note: Notification) -> Bool {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == SpotifyBridge.bundleID
    }

    private func safetyPoll() {
        if SpotifyBridge.isRunning { refresh() }
    }

    /// Coalesces bursts: a newer request replaces a pending one.
    func refresh(after delay: TimeInterval = 0) {
        pending?.cancel()
        pending = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            if Task.isCancelled { return }
            self?.performRefresh()
        }
    }

    private func performRefresh() {
        generation += 1
        let gen = generation
        queue.async { [weak self] in
            let snapshot = SpotifyBridge.readSnapshot()
            Task { @MainActor in self?.deliver(snapshot, generation: gen) }
        }
    }

    /// Stale results (an older read finishing after a newer one started) are dropped.
    private func deliver(_ snapshot: SpotifySnapshot, generation g: Int) {
        guard g == generation else { return }
        let retained = retention.accept(snapshot)
        if retained.availability != lastAvailability {
            lastAvailability = retained.availability
            Log.info("spotify availability=\(retained.availability)")
        }
        onChange?(retained)
    }

    /// Reports the real outcome. The UI never assumes success: state updates only when the follow-up read arrives.
    func perform(_ control: SpotifyControl, completion: @escaping @Sendable @MainActor (Bool) -> Void) {
        queue.async { [weak self] in
            let ok = SpotifyBridge.perform(control)
            Task { @MainActor in
                completion(ok)
                self?.refresh(after: 0.15)
            }
        }
    }
}
