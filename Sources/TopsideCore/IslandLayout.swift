import CoreGraphics
import Foundation

public struct IslandMetrics: Equatable, Sendable {
    public var height: CGFloat
    public var topOffset: CGFloat
    public var minWidth: CGFloat
    public var maxWidth: CGFloat
    public var horizontalPadding: CGFloat
    public var gap: CGFloat
    public var slotWidth: CGFloat
    public var peekExtra: CGFloat
    public var expandedExtra: CGFloat
    public var datePeekExtra: CGFloat
    public var dateExpandedExtra: CGFloat
    public var cornerRadius: CGFloat
    public var spotifyExpandedExtra: CGFloat
    public var compactSize: CGFloat
    /// Width of pinned (expanded) states. Peek and transient states stay at `maxWidth`.
    public var expandedWidth: CGFloat
    /// Extra height of the pinned Spotify player when a track (with progress) is known.
    public var spotifyPlayerExtra: CGFloat
    /// Concave "notch" flare on each top corner. 0 disables it. The ears are part of the pill's
    /// width: content is inset by `horizontalPadding + earWidth` so it keeps the same visual margin.
    public var earWidth: CGFloat

    /// Distance from the pill's outer edge to its content.
    public var contentInset: CGFloat { horizontalPadding + max(0, earWidth) }

    public init(height: CGFloat = 36, topOffset: CGFloat = 0, minWidth: CGFloat = 184, maxWidth: CGFloat = 284,
                horizontalPadding: CGFloat = 16, gap: CGFloat = 14, slotWidth: CGFloat = 48,
                peekExtra: CGFloat = 30, expandedExtra: CGFloat = 66,
                datePeekExtra: CGFloat = 44, dateExpandedExtra: CGFloat = 88, cornerRadius: CGFloat = 18,
                spotifyExpandedExtra: CGFloat = 84, compactSize: CGFloat = 22,
                expandedWidth: CGFloat = 288, spotifyPlayerExtra: CGFloat = 128, earWidth: CGFloat = 0) {
        self.height = height; self.topOffset = topOffset; self.minWidth = minWidth; self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding; self.gap = gap; self.slotWidth = slotWidth
        self.peekExtra = peekExtra; self.expandedExtra = expandedExtra
        self.datePeekExtra = datePeekExtra; self.dateExpandedExtra = dateExpandedExtra; self.cornerRadius = cornerRadius
        self.spotifyExpandedExtra = spotifyExpandedExtra; self.compactSize = compactSize
        self.expandedWidth = expandedWidth; self.spotifyPlayerExtra = spotifyPlayerExtra; self.earWidth = earWidth
    }
}

/// Measured content widths. batteryWidth == 0 means "no battery, hide it".
public struct IslandContent: Equatable, Sendable {
    public var clockWidth: CGFloat
    public var batteryWidth: CGFloat
    /// Controls to lay out in the pinned Spotify player (state-dependent).
    public var spotifyControls: [SpotifyControl]
    /// A track is playing or paused: the pinned Spotify view becomes a full player.
    public var spotifyHasTrack: Bool
    /// Spotify reported a duration and position, so the player shows a progress row.
    public var spotifyHasProgress: Bool
    /// Width of the Wi-Fi icon, or 0 for none. Only shown beside a battery, and dropped if it would not fit.
    public var wifiWidth: CGFloat
    public init(clockWidth: CGFloat, batteryWidth: CGFloat, spotifyControls: [SpotifyControl] = [],
                spotifyHasTrack: Bool = false, spotifyHasProgress: Bool = false, wifiWidth: CGFloat = 0) {
        self.wifiWidth = wifiWidth
        self.clockWidth = clockWidth; self.batteryWidth = batteryWidth; self.spotifyControls = spotifyControls
        self.spotifyHasTrack = spotifyHasTrack; self.spotifyHasProgress = spotifyHasProgress
    }
}

public enum HitTarget: Equatable, Sendable {
    case region(Region)             // collapsed band
    case detail(Region)             // area below the band while peeking/expanded
    case action(Region)             // clock/battery action button while expanded
    case compact                    // compact Spotify button in the band
    case control(SpotifyControl)    // pinned Spotify player control
    case audioOutput                // pinned player: output chip / switcher
    case dateCopy(DateCopyControl)  // pinned date copy action
    case outside
}

public enum DateCopyControl: Equatable, Hashable, Sendable, CaseIterable {
    case ad, bs, both
    public var title: String {
        switch self {
        case .ad: return "Copy AD"
        case .bs: return "Copy BS"
        case .both: return "Copy both"
        }
    }
    /// Label inside the segmented capsule, where the surrounding control already says "copy".
    public var shortTitle: String {
        switch self {
        case .ad: return "AD"
        case .bs: return "BS"
        case .both: return "Both"
        }
    }
}

public struct DateControlRect: Equatable, Sendable {
    public var control: DateCopyControl
    public var rect: CGRect
    public init(control: DateCopyControl, rect: CGRect) { self.control = control; self.rect = rect }
}

public struct ControlRect: Equatable, Sendable {
    public var control: SpotifyControl
    public var rect: CGRect
    public init(control: SpotifyControl, rect: CGRect) { self.control = control; self.rect = rect }
}

/// Layout of the pinned Spotify player (artwork, title, progress). Pill-local, top-left origin.
public struct SpotifyPlayerRects: Equatable, Sendable {
    public var artworkRect: CGRect
    public var titleRect: CGRect
    public var subtitleRect: CGRect
    /// All three are `.zero` when there is no progress row.
    public var elapsedRect: CGRect
    public var barRect: CGRect
    public var durationRect: CGRect
    public init(artworkRect: CGRect, titleRect: CGRect, subtitleRect: CGRect,
                elapsedRect: CGRect = .zero, barRect: CGRect = .zero, durationRect: CGRect = .zero) {
        self.artworkRect = artworkRect; self.titleRect = titleRect; self.subtitleRect = subtitleRect
        self.elapsedRect = elapsedRect; self.barRect = barRect; self.durationRect = durationRect
    }
}

/// All rects are in pill-local coordinates with a TOP-LEFT origin (y grows downward).
public struct IslandGeometry: Equatable, Sendable {
    public var size: CGSize
    public var bandHeight: CGFloat
    public var gap: CGFloat
    public var clockRect: CGRect
    public var batteryRect: CGRect
    /// Wi-Fi icon, a leading part of `batteryRect` (the hover region stays shared). `.zero` when not shown.
    public var wifiRect: CGRect = .zero
    /// Output chip in the pinned player. `.zero` elsewhere.
    public var outputRect: CGRect = .zero
    public var slotRect: CGRect
    public var artworkRect: CGRect
    public var playRect: CGRect
    public var detailRect: CGRect
    public var actionRect: CGRect
    public var controls: [ControlRect]
    public var dateControls: [DateControlRect]
    /// Non-nil only in the pinned Spotify state while a track is known.
    public var player: SpotifyPlayerRects?
    /// Width of each top-corner flare (0 = none). Part of `size.width`.
    public var ear: CGFloat
    /// First and second text lines of the detail area (empty when the pinned player or nothing is shown).
    public var primaryRect: CGRect
    public var secondaryRect: CGRect

    public init(size: CGSize, bandHeight: CGFloat, gap: CGFloat, clockRect: CGRect, batteryRect: CGRect,
                slotRect: CGRect, artworkRect: CGRect = .zero, playRect: CGRect = .zero,
                detailRect: CGRect, actionRect: CGRect, controls: [ControlRect] = [],
                dateControls: [DateControlRect] = [], player: SpotifyPlayerRects? = nil, ear: CGFloat = 0,
                primaryRect: CGRect = .zero, secondaryRect: CGRect = .zero) {
        self.size = size; self.bandHeight = bandHeight; self.gap = gap; self.clockRect = clockRect
        self.batteryRect = batteryRect; self.slotRect = slotRect; self.artworkRect = artworkRect; self.playRect = playRect
        self.detailRect = detailRect; self.actionRect = actionRect; self.controls = controls
        self.dateControls = dateControls; self.player = player; self.ear = ear
        self.primaryRect = primaryRect; self.secondaryRect = secondaryRect
    }

    public static let empty = IslandGeometry(size: .zero, bandHeight: 0, gap: 0, clockRect: .zero, batteryRect: .zero,
                                             slotRect: .zero, detailRect: .zero, actionRect: .zero)
}

public enum IslandLayout {
    /// The island is flush with the top of its window and only its bottom
    /// corners are rounded. Points outside those visible corners must pass
    /// through to the application underneath. With `earWidth > 0` the top
    /// corners also flare outward in a concave curve (the "notch" ears); the
    /// body is then inset by `earWidth` on each side.
    public static func containsVisibleShape(_ p: CGPoint, size: CGSize, cornerRadius: CGFloat,
                                            earWidth: CGFloat = 0) -> Bool {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.contains(p) else { return false }
        let ear = earWidth > 0 ? min(earWidth, size.width / 4, size.height / 2) : 0
        if ear > 0 {
            if p.x < ear {
                guard p.y < ear else { return false }
                let dx = p.x, dy = p.y - ear
                return dx * dx + dy * dy >= ear * ear
            }
            if p.x > size.width - ear {
                guard p.y < ear else { return false }
                let dx = p.x - size.width, dy = p.y - ear
                return dx * dx + dy * dy >= ear * ear
            }
        }
        let minX = ear, maxX = size.width - ear
        let radius = min(max(cornerRadius, 0), (maxX - minX) / 2, size.height / 2)
        guard radius > 0, p.y > size.height - radius else { return true }

        if p.x < minX + radius {
            let dx = p.x - (minX + radius)
            let dy = p.y - (size.height - radius)
            return dx * dx + dy * dy <= radius * radius
        }
        if p.x > maxX - radius {
            let dx = p.x - (maxX - radius)
            let dy = p.y - (size.height - radius)
            return dx * dx + dy * dy <= radius * radius
        }
        return true
    }

    public static func extraHeight(_ mode: IslandMode, _ m: IslandMetrics) -> CGFloat {
        switch mode {
        case .collapsed: return 0
        case .peek(.clock): return m.datePeekExtra
        case .peek, .transient: return m.peekExtra
        case .expanded(.clock): return m.dateExpandedExtra
        case .expanded(.spotify): return m.spotifyExpandedExtra
        case .expanded: return m.expandedExtra
        }
    }

    public static func geometry(metrics m: IslandMetrics, content c: IslandContent, mode: IslandMode) -> IslandGeometry {
        let ear = max(0, m.earWidth)
        let pad = m.horizontalPadding + ear
        let hasBattery = c.batteryWidth > 0
        func naturalWidth(wifi: CGFloat) -> CGFloat {
            pad * 2 + c.clockWidth + (hasBattery ? m.gap + c.batteryWidth + (wifi > 0 ? wifi + Self.wifiIconGap : 0) : 0)
                + m.gap + m.slotWidth
        }
        var wifiWidth = hasBattery ? max(0, c.wifiWidth) : 0
        if wifiWidth > 0, naturalWidth(wifi: wifiWidth) > m.maxWidth + ear * 2 { wifiWidth = 0 }   // no room: drop the icon
        let natural = naturalWidth(wifi: wifiWidth)
        let collapsedWidth = min(max(natural, m.minWidth + ear * 2), m.maxWidth + ear * 2)
        // Detail text and action labels need the full planned width; only the
        // resting island should hug its compact content. Pinned states get extra room.
        let width: CGFloat
        switch mode {
        case .collapsed: width = collapsedWidth
        case .expanded: width = max(m.expandedWidth, m.maxWidth) + ear * 2
        case .peek, .transient: width = m.maxWidth + ear * 2
        }

        let showsPlayer: Bool
        if case .expanded(.spotify) = mode { showsPlayer = c.spotifyHasTrack } else { showsPlayer = false }
        let extra: CGFloat
        if showsPlayer {
            extra = c.spotifyHasProgress ? m.spotifyPlayerExtra : m.spotifyPlayerExtra - Self.progressBlock
        } else {
            extra = extraHeight(mode, m)
        }

        let clock = CGRect(x: pad, y: 0, width: c.clockWidth, height: m.height)
        let groupWidth = hasBattery ? c.batteryWidth + (wifiWidth > 0 ? wifiWidth + Self.wifiIconGap : 0) : 0
        let battery = hasBattery ? CGRect(x: pad + c.clockWidth + m.gap, y: 0, width: groupWidth, height: m.height) : .zero
        let wifiRect = wifiWidth > 0 ? CGRect(x: battery.minX, y: 0, width: wifiWidth, height: m.height) : CGRect.zero
        var outputRect = CGRect.zero
        let slotX = width - pad - m.slotWidth
        let slot = CGRect(x: slotX, y: 0, width: m.slotWidth, height: m.height)
        let cs = m.compactSize
        let artwork = CGRect(x: slotX, y: (m.height - cs) / 2, width: cs, height: cs)
        let play = CGRect(x: slotX + m.slotWidth - cs, y: (m.height - cs) / 2, width: cs, height: cs)
        let detail = extra > 0 ? CGRect(x: 0, y: m.height, width: width, height: extra) : .zero

        var action = CGRect.zero
        var controls: [ControlRect] = []
        var dateControls: [DateControlRect] = []
        var player: SpotifyPlayerRects?
        if case .expanded(let region) = mode {
            if region == .spotify {
                if showsPlayer {
                    // Icon-only transport centred under the progress row; "open" sits at the top right.
                    let controlsY = m.height + extra - Self.playerControlsBlock      // 32 pt row + 12 pt bottom margin
                    let clusterX = (width - Self.transportWidth) / 2
                    var rects: [ControlRect] = []
                    for control in c.spotifyControls {
                        switch control {
                        case .previous:
                            rects.append(ControlRect(control: control, rect: CGRect(x: clusterX, y: controlsY, width: 40, height: 32)))
                        case .playPause:
                            rects.append(ControlRect(control: control, rect: CGRect(x: clusterX + 52, y: controlsY, width: 32, height: 32)))
                        case .next:
                            rects.append(ControlRect(control: control, rect: CGRect(x: clusterX + 96, y: controlsY, width: 40, height: 32)))
                        case .open:
                            rects.append(ControlRect(control: control, rect: CGRect(x: width - pad - 24, y: m.height + 6, width: 24, height: 24)))
                        case .connect, .openPrivacySettings:
                            break                                    // never offered while a track is known
                        }
                    }
                    controls = rects
                    outputRect = CGRect(x: pad, y: controlsY, width: Self.outputChipSize, height: 32)
                    let art = Self.playerArtworkSize
                    let textX = pad + art + 12
                    let hasOpen = c.spotifyControls.contains(.open)
                    let textW = max(0, width - pad - textX - (hasOpen ? 32 : 0))
                    var elapsed = CGRect.zero, bar = CGRect.zero, duration = CGRect.zero
                    if c.spotifyHasProgress {
                        let rowTop = controlsY - Self.progressBlock        // 12 pt row + 8 pt gap above the controls
                        let labelW: CGFloat = 34, gapX: CGFloat = 6
                        elapsed = CGRect(x: pad, y: rowTop, width: labelW, height: 12)
                        duration = CGRect(x: width - pad - labelW, y: rowTop, width: labelW, height: 12)
                        let barX = pad + labelW + gapX
                        bar = CGRect(x: barX, y: rowTop + 4.5, width: max(0, width - barX * 2), height: 3)
                    }
                    player = SpotifyPlayerRects(
                        artworkRect: CGRect(x: pad, y: m.height + 4, width: art, height: art),
                        titleRect: CGRect(x: textX, y: m.height + 8, width: textW, height: 20),
                        subtitleRect: CGRect(x: textX, y: m.height + 29, width: textW, height: 16),
                        elapsedRect: elapsed, barRect: bar, durationRect: duration)
                } else {
                    let n = c.spotifyControls.count
                    let rowY = m.height + extra - 36            // 24 pt row + 12 pt bottom margin
                    if n > 0 {
                        let spacing: CGFloat = 8
                        let w = (width - pad * 2 - spacing * CGFloat(n - 1)) / CGFloat(n)
                        controls = c.spotifyControls.enumerated().map { i, control in
                            ControlRect(control: control, rect: CGRect(x: pad + CGFloat(i) * (w + spacing), y: rowY, width: w, height: 24))
                        }
                    }
                }
            } else if region == .clock {
                // One segmented capsule: equal thirds, no gaps. The view draws the capsule outline and dividers.
                let values = DateCopyControl.allCases
                let w = (width - pad * 2) / CGFloat(values.count)
                dateControls = values.enumerated().map { index, control in
                    DateControlRect(control: control,
                                    rect: CGRect(x: pad + CGFloat(index) * w, y: m.height + extra - Self.dateCapsuleBlock,
                                                 width: w, height: Self.dateCapsuleHeight))
                }
            } else if region == .battery {
                // A small right-aligned text link level with the big percentage, not a full-width button.
                action = CGRect(x: width - pad - Self.batteryLinkWidth, y: m.height + 12,
                                width: Self.batteryLinkWidth, height: 20)
            }
        }

        var primary = CGRect.zero, secondary = CGRect.zero
        if extra > 0, !showsPlayer {
            let textW = max(0, width - pad * 2)
            switch mode {
            case .expanded(.clock):
                primary = CGRect(x: pad, y: m.height + 8, width: textW, height: 18)
                secondary = CGRect(x: pad, y: m.height + 27, width: textW, height: 16)
            case .expanded(.battery):
                primary = CGRect(x: pad, y: m.height + 8, width: max(0, textW - Self.batteryLinkWidth - 8), height: 28)
                secondary = CGRect(x: pad, y: m.height + 38, width: textW, height: 16)
            default:
                primary = CGRect(x: pad, y: m.height + 5, width: textW, height: 20)
                secondary = CGRect(x: pad, y: m.height + 25, width: textW, height: 16)
            }
        }

        var result = IslandGeometry(size: CGSize(width: width, height: m.height + extra), bandHeight: m.height, gap: m.gap,
                              clockRect: clock, batteryRect: battery, slotRect: slot, artworkRect: artwork, playRect: play,
                              detailRect: detail, actionRect: action, controls: controls, dateControls: dateControls,
                              player: player, ear: ear, primaryRect: primary, secondaryRect: secondary)
        result.wifiRect = wifiRect
        result.outputRect = outputRect
        return result
    }

    /// Wi-Fi icon width and the space between it and the battery glyph.
    public static let wifiIconWidth: CGFloat = 16
    public static let wifiIconGap: CGFloat = 12
    static let outputChipSize: CGFloat = 32

    /// 12 pt progress row plus the 8 pt gap that separates it from the controls.
    static let progressBlock: CGFloat = 20
    static let playerArtworkSize: CGFloat = 52
    /// prev (40) + gap (12) + play (32) + gap (12) + next (40).
    static let transportWidth: CGFloat = 136
    /// 32 pt transport row plus a 12 pt bottom margin.
    static let playerControlsBlock: CGFloat = 44
    /// 26 pt segmented capsule plus a 12 pt bottom margin.
    static let dateCapsuleHeight: CGFloat = 26
    static let dateCapsuleBlock: CGFloat = 38
    static let batteryLinkWidth: CGFloat = 132

    /// AppKit screen coordinates (bottom-left origin). Top-attached, horizontally centered on the display frame.
    public static func panelFrame(geometry g: IslandGeometry, displayFrame: CGRect, topOffset: CGFloat, scale: CGFloat) -> CGRect {
        let s = max(scale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v * s).rounded() / s }
        let x = snap(displayFrame.midX - g.size.width / 2)
        let y = snap(displayFrame.maxY - topOffset - g.size.height)
        return CGRect(x: x, y: y, width: g.size.width, height: g.size.height)
    }

    public static func hit(_ p: CGPoint, geometry g: IslandGeometry, mode: IslandMode,
                           cornerRadius: CGFloat? = nil) -> HitTarget {
        guard containsVisibleShape(p, size: g.size, cornerRadius: cornerRadius ?? g.bandHeight / 2,
                                   earWidth: g.ear) else { return .outside }
        if p.y >= g.bandHeight {
            guard let r = mode.region else { return .outside }
            if case .expanded = mode {
                if let hit = g.controls.first(where: { $0.rect.contains(p) }) { return .control(hit.control) }
                if g.outputRect.contains(p) { return .audioOutput }
                if let hit = g.dateControls.first(where: { $0.rect.contains(p) }) { return .dateCopy(hit.control) }
                if g.actionRect.contains(p) { return .action(r) }
            }
            return .detail(r)
        }
        // The pinned player replaces the compact artwork/play button, so it must not be clickable there.
        if g.player == nil, g.playRect.contains(p) { return .compact }
        let hasBattery = g.batteryRect.width > 0
        let clockEnd = hasBattery ? (g.clockRect.maxX + g.batteryRect.minX) / 2 : g.clockRect.maxX + g.gap / 2
        if p.x < clockEnd { return .region(.clock) }
        if hasBattery && p.x < g.batteryRect.maxX + g.gap / 2 { return .region(.battery) }
        return .region(.spotify)
    }
}
