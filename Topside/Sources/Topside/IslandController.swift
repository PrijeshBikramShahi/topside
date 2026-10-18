import AppKit
import Combine
import TopsideCore

/// Owns the single island: wires services -> model, pointer input -> reducer, reducer -> panel frame.
@MainActor
final class IslandController: NSObject, IslandRootViewDelegate {
    enum SuppressReason: Hashable { case fullscreen, locked, sleeping, userHidden }

    private let prefs = Preferences.shared
    private let provider: DisplayProviding = ActiveDisplayProvider()
    private let model: IslandModel
    private let host: IslandHost
    private let clock = ClockService()
    private let battery = BatteryService()
    private let fullscreen = FullscreenMonitor()
    private let spotify = SpotifyService()
    private let artwork = ArtworkLoader()
    private var currentArtworkURL: URL?
    private var noticeTask: Task<Void, Never>?

    private var interaction = InteractionState()
    private var timerTask: Task<Void, Never>?
    private var context: DisplayContext?
    private var reasons = Set<SuppressReason>()
    private var globalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    override init() {
        let m = IslandModel()
        model = m
        host = IslandHost(model: m)
        super.init()
    }

    var isUserHidden: Bool { reasons.contains(.userHidden) }
    func toggleUserHidden() { setSuppressed(.userHidden, !isUserHidden) }

    // MARK: Lifecycle

    func start() {
        host.rootView.delegate = self
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        registerObservers()

        clock.onTick = { [weak self] in self?.tick() }
        battery.onChange = { [weak self] snapshot in self?.batteryChanged(snapshot) }
        spotify.onChange = { [weak self] snapshot in self?.spotifyChanged(snapshot) }
        fullscreen.displayFrame = { [weak self] in self?.context?.frame }
        fullscreen.onChange = { [weak self] on in self?.setSuppressed(.fullscreen, on) }
        fullscreen.enabled = prefs.hideInFullscreen

        prefs.changes.receive(on: RunLoop.main).sink { [weak self] _ in self?.prefsChanged() }.store(in: &cancellables)

        refreshDisplay()
        clock.start()
        battery.start()
        spotify.start()
        fullscreen.start()
        installGlobalMonitor()
        host.show()
        Log.info("island started")
    }

    private func registerObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(didWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reduceMotionChanged),
                       name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(locked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(unlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    /// Outside-click dismissal: a global mouse monitor needs no permission and never sees clicks on our own panel.
    private func installGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.send(.outsideClick) }
        }
    }

    @objc private func screensChanged() { refreshDisplay() }
    @objc private func willSleep() { setSuppressed(.sleeping, true) }
    @objc private func didWake() { setSuppressed(.sleeping, false); refreshDisplay(); battery.refresh(); spotify.refresh(after: 1.0) }
    @objc private func locked() { setSuppressed(.locked, true) }
    @objc private func unlocked() { setSuppressed(.locked, false); refreshDisplay() }
    @objc private func reduceMotionChanged() { model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Model updates

    private func tick() {
        model.clockText = ClockFormat.string(for: Date(), style: prefs.clockStyle)
        model.detailText = detailText(for: interaction.mode)
    }

    private func batteryChanged(_ snapshot: PowerSnapshot) {
        let display = BatteryMapper.map(snapshot)
        guard display != model.battery else { return }
        model.battery = display
        relayout(animated: true)
    }

    private func spotifyChanged(_ snapshot: SpotifySnapshot) {
        let display = SpotifyMapper.map(snapshot)
        let url = display.artworkURL
        if url != currentArtworkURL {
            currentArtworkURL = url
            model.artwork = nil          // previous track's art must never show on a new track
            artwork.cancel()
            if let url {
                artwork.load(url, points: 22, scale: context?.scale ?? 2) { [weak self] image in
                    guard let self, self.currentArtworkURL == url else { return }
                    self.model.artwork = image
                }
            }
        }
        guard display != model.spotify else { return }
        model.spotify = display
        relayout(animated: true)
    }

    private func showNotice(_ text: String) {
        model.spotifyNotice = text
        relayout(animated: false)
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Timing.transientDuration * 1_000_000_000))
            if Task.isCancelled { return }
            self?.model.spotifyNotice = nil
            self?.relayout(animated: false)
        }
    }

    private func prefsChanged() {
        fullscreen.enabled = prefs.hideInFullscreen
        tick()
        relayout(animated: false)
    }

    private func refreshDisplay() {
        let new = provider.currentContext()
        if new != context {
            context = new
            if let c = new {
                Log.info("display id=\(c.id) frame=\(c.frame) menuBar=\(c.menuBarHeight) scale=\(c.scale)")
            }
            send(.escape)   // drop any pinned panel that may now be on the wrong display
        }
        tick()
        relayout(animated: false)
    }

    private func detailText(for mode: IslandMode) -> String {
        switch mode.region {
        case .clock?: return Self.dateFormatter.string(from: Date())
        case .battery?: return model.battery.detail
        case .spotify?:
            if let notice = model.spotifyNotice { return notice }
            let d = model.spotify
            if case .expanded = mode, d.availability == .playing || d.availability == .paused, !d.title.isEmpty { return d.title }
            return d.detail
        case nil: return ""
        }
    }

    private func detailSubtext(for mode: IslandMode) -> String {
        guard case .expanded(.spotify) = mode, model.spotifyNotice == nil else { return "" }
        let d = model.spotify
        return (d.availability == .playing || d.availability == .paused) ? d.subtitle : ""
    }

    private func actionTitle(for mode: IslandMode) -> String {
        guard case .expanded(let r) = mode else { return "" }
        switch r {
        case .clock: return "Open Date & Time settings"
        case .battery: return "Open Battery settings"
        case .spotify: return ""          // Spotify uses per-state controls instead
        }
    }

    private func measuredClockWidth() -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        let text = ClockFormat.measurementString(style: prefs.clockStyle)
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) + 4
    }

    private func relayout(animated: Bool) {
        guard let ctx = context else { return }
        let metrics = prefs.metrics
        let batteryWidth: CGFloat = model.battery.isHidden ? 0 : BatteryLayout.width(showsPercent: model.battery.showsPercent)
        let geometry = IslandLayout.geometry(metrics: metrics,
                                             content: IslandContent(clockWidth: measuredClockWidth(), batteryWidth: batteryWidth,
                                                                    spotifyControls: model.spotify.controls),
                                             mode: interaction.mode)
        model.metrics = metrics
        model.geometry = geometry
        model.mode = interaction.mode
        model.detailText = detailText(for: interaction.mode)
        model.detailSubtext = detailSubtext(for: interaction.mode)
        model.actionTitle = actionTitle(for: interaction.mode)
        let frame = IslandLayout.panelFrame(geometry: geometry, displayFrame: ctx.frame, topOffset: metrics.topOffset, scale: ctx.scale)
        host.setFrame(frame, animated: animated && !model.reduceMotion)
    }

    // MARK: Suppression (fullscreen, lock, sleep, user hide)

    private func setSuppressed(_ reason: SuppressReason, _ on: Bool) {
        let was = !reasons.isEmpty
        if on { reasons.insert(reason) } else { reasons.remove(reason) }
        let now = !reasons.isEmpty
        guard now != was else { return }
        send(.setSuppressed(now))
        if now {
            host.hide()
        } else {
            relayout(animated: false)
            host.show()
        }
        Log.info("suppressed=\(now) reasons=\(reasons.map { "\($0)" }.sorted())")
    }

    // MARK: Interaction

    private func send(_ event: InteractionEvent) {
        let before = interaction.mode
        let effects = InteractionReducer.reduce(&interaction, event)
        for effect in effects {
            switch effect {
            case .cancelTimers:
                timerTask?.cancel()
                timerTask = nil
            case .startDwell(let token, let delay):
                schedule(after: delay) { [weak self] in self?.send(.dwellElapsed(token: token)) }
            case .startGrace(let token, let delay):
                schedule(after: delay) { [weak self] in self?.graceFired(token: token) }
            }
        }
        if interaction.mode != before { relayout(animated: true) }
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        timerTask?.cancel()
        timerTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }
            block()
        }
    }

    /// Resizing the panel can produce a spurious mouseExited. Before collapsing, check where the pointer really is.
    private func graceFired(token: Int) {
        if host.frame.contains(NSEvent.mouseLocation) {
            let p = host.rootView.convert(host.panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            send(.pointerMoved(region(for: p)))
        } else {
            send(.graceElapsed(token: token))
        }
    }

    private func region(for p: CGPoint) -> Region? {
        switch IslandLayout.hit(p, geometry: model.geometry, mode: interaction.mode) {
        case .region(let r), .detail(let r), .action(let r): return r
        case .compact, .control: return .spotify
        case .outside: return nil
        }
    }

    func rootView(_ view: IslandRootView, pointerMovedTo point: CGPoint?) {
        guard let point else { send(.pointerMoved(nil)); return }
        send(.pointerMoved(region(for: point)))
    }

    func rootView(_ view: IslandRootView, clickedAt point: CGPoint) {
        switch IslandLayout.hit(point, geometry: model.geometry, mode: interaction.mode) {
        case .region(let r): send(.clicked(r))
        case .action(let r): performAction(for: r)
        case .compact: if let control = model.spotify.compactControl { performSpotify(control) }
        case .control(let control): performSpotify(control)
        case .detail, .outside: break
        }
    }

    private func performSpotify(_ control: SpotifyControl) {
        switch control {
        case .open:
            openSpotify()
            send(.escape)
        case .openPrivacySettings:
            let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            if let url = URL(string: pane), NSWorkspace.shared.open(url) {
                Log.info("opened Automation settings")
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
            send(.escape)
        case .previous, .playPause, .next, .connect:
            spotify.perform(control) { [weak self] ok in
                guard let self, !ok else { return }
                self.showNotice(control == .connect ? "Spotify control not granted" : "Couldn't control Spotify")
            }
        }
    }

    private func openSpotify() {
        guard let url = SpotifyBridge.installedURL else { showNotice("Spotify isn't installed"); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if error != nil { self?.showNotice("Couldn't open Spotify") } else { self?.spotify.refresh(after: 1.5) }
            }
        }
    }

    private func performAction(for region: Region) {
        let urlString = region == .battery
            ? "x-apple.systempreferences:com.apple.Battery-Settings.extension"
            : "x-apple.systempreferences:com.apple.Date-Time-Settings.extension"
        // Report honestly: if the pane URL fails, fall back to opening System Settings itself.
        if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
            Log.info("opened settings pane for \(region)")
        } else {
            Log.info("settings pane URL failed for \(region); opening System Settings")
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
        send(.escape)
    }
}
