import AppKit
import Combine
import TopsideCore

/// Owns the single island: wires services -> model, pointer input -> reducer, reducer -> panel frame.
@MainActor
final class IslandController: NSObject, IslandRootViewDelegate {
    enum SuppressReason: Hashable { case fullscreen, menuTracking, locked, sleeping, userHidden }

    private let prefs = Preferences.shared
    private let provider: DisplayProviding = ActiveDisplayProvider()
    private let model: IslandModel
    private let host: IslandHost
    private let clock = ClockService()
    private let battery = BatteryService()
    private let fullscreen = FullscreenMonitor()
    private let fullscreenReveal = FullscreenRevealMonitor()
    private let menuTracking = MenuTrackingMonitor()
    private let spotify = SpotifyService()
    private let audio = AudioOutputService()
    private let artwork = ArtworkLoader()
    private var currentArtworkURL: URL?
    private var noticeTask: Task<Void, Never>?
    private var lastBatteryStatus: BatteryStatus?
    private var lastAudioOutputID: UInt32?
    private var keyboardFocusIndex = 0

    private var interaction = InteractionState()
    private var timerTask: Task<Void, Never>?
    private var context: DisplayContext?
    private var reasons = Set<SuppressReason>()
    private var globalMonitor: Any?
    private var cancellables = Set<AnyCancellable>()

    override init() {
        let m = IslandModel()
        model = m
        host = IslandHost(model: m)
        super.init()
    }

    var isUserHidden: Bool { reasons.contains(.userHidden) }
    func toggleUserHidden() { setSuppressed(.userHidden, !isUserHidden) }
    func setOwnMenuTracking(_ tracking: Bool) { menuTracking.setOwnMenuTracking(tracking) }

    // MARK: Lifecycle

    func start() {
        host.rootView.delegate = self
        model.activateSpotifyControl = { [weak self] in self?.performSpotify($0) }
        model.activateDateCopy = { [weak self] in self?.performDateCopy($0) }
        model.activateRegionAction = { [weak self] in self?.performAction(for: $0) }
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        registerObservers()

        clock.onTick = { [weak self] in self?.tick() }
        battery.onChange = { [weak self] snapshot in self?.batteryChanged(snapshot) }
        spotify.onChange = { [weak self] snapshot in self?.spotifyChanged(snapshot) }
        audio.onChange = { [weak self] snapshot in self?.audioOutputChanged(snapshot) }
        fullscreen.displayContext = { [weak self] in self?.context }
        fullscreen.onChange = { [weak self] on in self?.fullscreenChanged(on) }
        fullscreenReveal.displayFrame = { [weak self] in self?.context?.frame }
        fullscreenReveal.islandFrame = { [weak self] in self?.host.frame }
        fullscreenReveal.onReveal = { [weak self] in self?.revealInFullscreen() }
        fullscreenReveal.onHide = { [weak self] in self?.hideInFullscreen() }
        menuTracking.islandFrame = { [weak self] in self?.host.frame }
        menuTracking.onChange = { [weak self] on in
            guard let self else { return }
            // Moving to the fullscreen reveal zone also exposes macOS's menu-bar
            // layer. FullscreenRevealMonitor owns visibility in that state.
            guard !self.fullscreen.isFullscreen else { return }
            self.setSuppressed(.menuTracking, on)
        }
        fullscreen.enabled = prefs.hideInFullscreen

        prefs.changes.receive(on: RunLoop.main).sink { [weak self] _ in self?.prefsChanged() }.store(in: &cancellables)

        refreshDisplay()
        clock.start()
        battery.start()
        spotify.start()
        audio.start()
        fullscreen.start()
        fullscreenReveal.start()
        menuTracking.start()
        installGlobalMonitor()
        // FullscreenMonitor may synchronously suppress the island during start().
        // Never override that decision with an unconditional order-front.
        if reasons.isEmpty { host.show() }
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
            Task { @MainActor in
                self?.menuTracking.noteGlobalMouseDown(at: NSEvent.mouseLocation)
                self?.send(.outsideClick)
            }
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
        let date = DualDateFormatter.string(for: Date())
        model.adDateText = date.ad
        model.bsDateText = date.bs
        model.combinedDateText = date.combined
        model.detailText = detailText(for: interaction.mode)
    }

    private func batteryChanged(_ snapshot: PowerSnapshot) {
        let display = BatteryMapper.map(snapshot)
        guard display != model.battery else { return }
        let previousStatus = lastBatteryStatus
        lastBatteryStatus = display.status
        model.battery = display
        if let previousStatus, previousStatus != display.status,
           let message = powerTransitionText(from: previousStatus, to: display) {
            Log.info("power transition=\(message)")
            showTransient(message, region: .battery)
            ensureVisibleAfterPowerTransition()
        } else {
            relayout(animated: true)
        }
    }

    private func spotifyChanged(_ snapshot: SpotifySnapshot) {
        let display = SpotifyMapper.map(snapshot)
        let url = display.artworkURL
        if url != currentArtworkURL {
            currentArtworkURL = url
            reloadArtwork(url)
        }
        guard display != model.spotify else { return }
        model.spotify = display
        relayout(animated: true)
    }

    private func reloadArtwork(_ url: URL?) {
        model.artwork = nil          // previous/incorrect-scale art must never remain visible
        artwork.cancel()
        guard let url else { return }
        artwork.load(url, points: 22, scale: context?.scale ?? 2) { [weak self] image in
            guard let self, self.currentArtworkURL == url else { return }
            self.model.artwork = image
        }
    }

    private func audioOutputChanged(_ snapshot: AudioOutputSnapshot) {
        defer { lastAudioOutputID = snapshot.id }
        guard let previous = lastAudioOutputID, previous != snapshot.id else { return }
        Log.info("audio output id=\(snapshot.id) name=\(snapshot.name)")
        showTransient("Audio output · \(snapshot.name)", region: .audio)
    }

    private func showTransient(_ text: String, region: Region, spotifyFailure: Bool = false) {
        if spotifyFailure { model.spotifyNotice = text }
        model.transientText = text
        if case .expanded = interaction.mode {
            // Keep the user's explicit panel in place.
            relayout(animated: false)
        } else {
            let previousMode = interaction.mode
            send(.showTransient(region))
            // Suppression may reject the reducer event; update text without
            // issuing a second frame mutation when the mode already changed.
            if interaction.mode == previousMode { relayout(animated: false) }
        }
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Timing.transientDuration * 1_000_000_000))
            if Task.isCancelled { return }
            guard let self else { return }
            self.model.transientText = nil
            if spotifyFailure { self.model.spotifyNotice = nil }
            if case .transient(region) = self.interaction.mode {
                self.send(.escape)
            } else {
                self.relayout(animated: false)
            }
        }
    }

    private func ensureVisibleAfterPowerTransition() {
        guard reasons.isEmpty else { return }
        host.show()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled, self.reasons.isEmpty else { return }
            self.host.show()
        }
    }

    private func powerTransitionText(from old: BatteryStatus, to display: BatteryDisplay) -> String? {
        let percent = display.percent.map { " · \($0)%" } ?? ""
        switch display.status {
        case .charging: return "Charging\(percent)"
        case .charged: return "Battery charged"
        case .pluggedNotCharging: return "Plugged in\(percent)"
        case .discharging where old == .charging || old == .charged || old == .pluggedNotCharging:
            return "Running on battery\(percent)"
        case .noBattery, .unknown, .discharging:
            return nil
        }
    }

    private func prefsChanged() {
        fullscreen.enabled = prefs.hideInFullscreen
        tick()
        relayout(animated: false)
    }

    private func refreshDisplay() {
        let new = provider.currentContext()
        let scaleChanged = new?.scale != context?.scale
        if new != context {
            context = new
            if let c = new {
                Log.info("display id=\(c.id) frame=\(c.frame) menuBar=\(c.menuBarHeight) scale=\(c.scale)")
            }
            send(.escape)   // drop any pinned panel that may now be on the wrong display
        }
        if scaleChanged { reloadArtwork(currentArtworkURL) }
        tick()
        relayout(animated: false)
        // The fullscreen heuristic compares against the active display frame.
        // Re-evaluate whenever that frame may have changed (hot-plug, clamshell,
        // resolution/scaling change, or moving the menu bar to another screen).
        fullscreen.recheck()
    }

    private func detailText(for mode: IslandMode) -> String {
        if case .transient = mode, let text = model.transientText { return text }
        switch mode.region {
        case .clock?:
            if case .expanded(.clock) = mode, let feedback = model.transientText,
               feedback.hasPrefix("Copied") { return feedback }
            return model.adDateText
        case .battery?: return model.battery.detail
        case .spotify?:
            if let notice = model.spotifyNotice { return notice }
            let d = model.spotify
            if case .expanded = mode, d.availability == .playing || d.availability == .paused, !d.title.isEmpty { return d.title }
            return d.detail
        case .audio?: return model.transientText ?? "Audio output changed"
        case nil: return ""
        }
    }

    private func detailSubtext(for mode: IslandMode) -> String {
        switch mode {
        case .peek(.clock), .expanded(.clock):
            return model.bsDateText
        case .expanded(.spotify) where model.spotifyNotice == nil:
            let d = model.spotify
            return (d.availability == .playing || d.availability == .paused) ? d.subtitle : ""
        default:
            return ""
        }
    }

    private func actionTitle(for mode: IslandMode) -> String {
        guard case .expanded(let r) = mode else { return "" }
        switch r {
        case .clock: return "Copy AD + BS"
        case .battery: return "Open Battery settings"
        case .spotify: return ""          // Spotify uses per-state controls instead
        case .audio: return ""
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
        updateKeyboardFocus()
        host.updateInteractiveShape(size: geometry.size, cornerRadius: metrics.cornerRadius)
        let frame = IslandLayout.panelFrame(geometry: geometry, displayFrame: ctx.frame, topOffset: metrics.topOffset, scale: ctx.scale)
        host.setFrame(frame, animated: animated && !model.reduceMotion)
    }

    // MARK: Suppression (fullscreen, lock, sleep, user hide)

    private func fullscreenChanged(_ fullscreenNow: Bool) {
        fullscreenReveal.setActive(fullscreenNow)
        if fullscreenNow {
            setSuppressed(.fullscreen, true)
            setSuppressed(.menuTracking, false)
        } else {
            setSuppressed(.menuTracking, menuTracking.isTracking)
            setSuppressed(.fullscreen, false)
        }
    }

    private func revealInFullscreen() {
        guard fullscreen.isFullscreen else { return }
        setSuppressed(.fullscreen, false)
        Log.info("fullscreenReveal=true")
    }

    private func hideInFullscreen() {
        guard fullscreen.isFullscreen else { return }
        setSuppressed(.fullscreen, true)
        Log.info("fullscreenReveal=false")
    }

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
        if interaction.mode != before {
            let wasExpanded: Bool
            let isExpanded: Bool
            if case .expanded = before { wasExpanded = true } else { wasExpanded = false }
            if case .expanded = interaction.mode { isExpanded = true } else { isExpanded = false }
            if wasExpanded != isExpanded {
                keyboardFocusIndex = 0
                host.setKeyboardInteraction(isExpanded)
            }
            relayout(animated: true)
        }
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
        switch IslandLayout.hit(p, geometry: model.geometry, mode: interaction.mode,
                                cornerRadius: model.metrics.cornerRadius) {
        case .region(let r), .detail(let r), .action(let r): return r
        case .dateCopy: return .clock
        case .compact, .control: return .spotify
        case .outside: return nil
        }
    }

    func rootView(_ view: IslandRootView, pointerMovedTo point: CGPoint?) {
        guard let point else {
            model.hoveredTarget = .outside
            send(.pointerMoved(nil))
            return
        }
        let target = IslandLayout.hit(point, geometry: model.geometry, mode: interaction.mode,
                                      cornerRadius: model.metrics.cornerRadius)
        model.hoveredTarget = target
        send(.pointerMoved(region(for: point)))
    }

    func rootView(_ view: IslandRootView, clickedAt point: CGPoint) {
        switch IslandLayout.hit(point, geometry: model.geometry, mode: interaction.mode,
                                cornerRadius: model.metrics.cornerRadius) {
        case .region(let r): send(.clicked(r))
        case .action(let r): performAction(for: r)
        case .compact: if let control = model.spotify.compactControl { performSpotify(control) }
        case .control(let control): performSpotify(control)
        case .dateCopy(let control): performDateCopy(control)
        case .detail, .outside: break
        }
    }

    private func performDateCopy(_ control: DateCopyControl) {
        let value: String
        switch control {
        case .ad: value = model.adDateText
        case .bs: value = model.bsDateText
        case .both: value = model.combinedDateText
        }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(value, forType: .string)
        showTransient(copied ? "Copied \(control == .both ? "AD + BS" : control == .ad ? "AD" : "BS")"
                             : "Couldn't copy date", region: .clock)
    }

    func rootViewRequestedDismissal(_ view: IslandRootView) {
        send(.escape)
    }

    func rootView(_ view: IslandRootView, moveKeyboardFocusBy delta: Int) {
        let targets = keyboardTargets()
        guard !targets.isEmpty else { return }
        keyboardFocusIndex = (keyboardFocusIndex + delta % targets.count + targets.count) % targets.count
        model.keyboardFocusRect = targets[keyboardFocusIndex].1
    }

    func rootViewRequestedKeyboardActivation(_ view: IslandRootView) {
        let targets = keyboardTargets()
        guard targets.indices.contains(keyboardFocusIndex) else { return }
        activate(targets[keyboardFocusIndex].0)
    }

    private func keyboardTargets() -> [(HitTarget, CGRect)] {
        guard case .expanded(let region) = interaction.mode else { return [] }
        switch region {
        case .clock:
            return model.geometry.dateControls.map { (.dateCopy($0.control), $0.rect) }
        case .battery:
            return model.geometry.actionRect.isEmpty ? [] : [(.action(.battery), model.geometry.actionRect)]
        case .spotify:
            return model.geometry.controls.map { (.control($0.control), $0.rect) }
        case .audio:
            return []
        }
    }

    private func updateKeyboardFocus() {
        let targets = keyboardTargets()
        guard !targets.isEmpty else {
            model.keyboardFocusRect = nil
            return
        }
        keyboardFocusIndex = min(keyboardFocusIndex, targets.count - 1)
        model.keyboardFocusRect = targets[keyboardFocusIndex].1
    }

    private func activate(_ target: HitTarget) {
        switch target {
        case .action(let region): performAction(for: region)
        case .control(let control): performSpotify(control)
        case .dateCopy(let control): performDateCopy(control)
        case .compact:
            if let control = model.spotify.compactControl { performSpotify(control) }
        case .region(let region): send(.clicked(region))
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
                self.showTransient(control == .connect ? "Spotify control not granted" : "Couldn't control Spotify",
                                   region: .spotify, spotifyFailure: true)
            }
        }
    }

    private func openSpotify() {
        guard let url = SpotifyBridge.installedURL else {
            showTransient("Spotify isn't installed", region: .spotify, spotifyFailure: true)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { [weak self] _, error in
            Task { @MainActor in
                if error != nil {
                    self?.showTransient("Couldn't open Spotify", region: .spotify, spotifyFailure: true)
                } else {
                    self?.spotify.refresh(after: 1.5)
                }
            }
        }
    }

    private func performAction(for region: Region) {
        let urlString: String
        switch region {
        case .battery: urlString = "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        case .audio: urlString = "x-apple.systempreferences:com.apple.Sound-Settings.extension"
        case .clock, .spotify: return
        }
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
