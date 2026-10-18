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
    public var cornerRadius: CGFloat
    public var spotifyExpandedExtra: CGFloat
    public var compactSize: CGFloat

    public init(height: CGFloat = 36, topOffset: CGFloat = 0, minWidth: CGFloat = 184, maxWidth: CGFloat = 240,
                horizontalPadding: CGFloat = 14, gap: CGFloat = 10, slotWidth: CGFloat = 48,
                peekExtra: CGFloat = 30, expandedExtra: CGFloat = 66, cornerRadius: CGFloat = 18,
                spotifyExpandedExtra: CGFloat = 84, compactSize: CGFloat = 22) {
        self.height = height; self.topOffset = topOffset; self.minWidth = minWidth; self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding; self.gap = gap; self.slotWidth = slotWidth
        self.peekExtra = peekExtra; self.expandedExtra = expandedExtra; self.cornerRadius = cornerRadius
        self.spotifyExpandedExtra = spotifyExpandedExtra; self.compactSize = compactSize
    }
}

/// Measured content widths. batteryWidth == 0 means "no battery, hide it".
public struct IslandContent: Equatable, Sendable {
    public var clockWidth: CGFloat
    public var batteryWidth: CGFloat
    /// Controls to lay out in the pinned Spotify player (state-dependent).
    public var spotifyControls: [SpotifyControl]
    public init(clockWidth: CGFloat, batteryWidth: CGFloat, spotifyControls: [SpotifyControl] = []) {
        self.clockWidth = clockWidth; self.batteryWidth = batteryWidth; self.spotifyControls = spotifyControls
    }
}

public enum HitTarget: Equatable, Sendable {
    case region(Region)             // collapsed band
    case detail(Region)             // area below the band while peeking/expanded
    case action(Region)             // clock/battery action button while expanded
    case compact                    // compact Spotify button in the band
    case control(SpotifyControl)    // pinned Spotify player control
    case outside
}

public struct ControlRect: Equatable, Sendable {
    public var control: SpotifyControl
    public var rect: CGRect
    public init(control: SpotifyControl, rect: CGRect) { self.control = control; self.rect = rect }
}

/// All rects are in pill-local coordinates with a TOP-LEFT origin (y grows downward).
public struct IslandGeometry: Equatable, Sendable {
    public var size: CGSize
    public var bandHeight: CGFloat
    public var gap: CGFloat
    public var clockRect: CGRect
    public var batteryRect: CGRect
    public var slotRect: CGRect
    public var artworkRect: CGRect
    public var playRect: CGRect
    public var detailRect: CGRect
    public var actionRect: CGRect
    public var controls: [ControlRect]

    public init(size: CGSize, bandHeight: CGFloat, gap: CGFloat, clockRect: CGRect, batteryRect: CGRect,
                slotRect: CGRect, artworkRect: CGRect = .zero, playRect: CGRect = .zero,
                detailRect: CGRect, actionRect: CGRect, controls: [ControlRect] = []) {
        self.size = size; self.bandHeight = bandHeight; self.gap = gap; self.clockRect = clockRect
        self.batteryRect = batteryRect; self.slotRect = slotRect; self.artworkRect = artworkRect; self.playRect = playRect
        self.detailRect = detailRect; self.actionRect = actionRect; self.controls = controls
    }

    public static let empty = IslandGeometry(size: .zero, bandHeight: 0, gap: 0, clockRect: .zero, batteryRect: .zero,
                                             slotRect: .zero, detailRect: .zero, actionRect: .zero)
}

public enum IslandLayout {
    public static func extraHeight(_ mode: IslandMode, _ m: IslandMetrics) -> CGFloat {
        switch mode {
        case .collapsed: return 0
        case .peek: return m.peekExtra
        case .expanded(.spotify): return m.spotifyExpandedExtra
        case .expanded: return m.expandedExtra
        }
    }

    public static func geometry(metrics m: IslandMetrics, content c: IslandContent, mode: IslandMode) -> IslandGeometry {
        let pad = m.horizontalPadding
        let hasBattery = c.batteryWidth > 0
        let natural = pad * 2 + c.clockWidth + (hasBattery ? m.gap + c.batteryWidth : 0) + m.gap + m.slotWidth
        let width = min(max(natural, m.minWidth), m.maxWidth)
        let extra = extraHeight(mode, m)

        let clock = CGRect(x: pad, y: 0, width: c.clockWidth, height: m.height)
        let battery = hasBattery ? CGRect(x: pad + c.clockWidth + m.gap, y: 0, width: c.batteryWidth, height: m.height) : .zero
        let slotX = width - pad - m.slotWidth
        let slot = CGRect(x: slotX, y: 0, width: m.slotWidth, height: m.height)
        let cs = m.compactSize
        let artwork = CGRect(x: slotX, y: (m.height - cs) / 2, width: cs, height: cs)
        let play = CGRect(x: slotX + m.slotWidth - cs, y: (m.height - cs) / 2, width: cs, height: cs)
        let detail = extra > 0 ? CGRect(x: 0, y: m.height, width: width, height: extra) : .zero

        var action = CGRect.zero
        var controls: [ControlRect] = []
        if case .expanded(let region) = mode {
            if region == .spotify {
                let n = c.spotifyControls.count
                if n > 0 {
                    let spacing: CGFloat = 6
                    let rowY = m.height + m.spotifyExpandedExtra - 36
                    let w = (width - pad * 2 - spacing * CGFloat(n - 1)) / CGFloat(n)
                    controls = c.spotifyControls.enumerated().map { i, control in
                        ControlRect(control: control, rect: CGRect(x: pad + CGFloat(i) * (w + spacing), y: rowY, width: w, height: 24))
                    }
                }
            } else {
                action = CGRect(x: pad, y: m.height + 30, width: width - pad * 2, height: 24)
            }
        }

        return IslandGeometry(size: CGSize(width: width, height: m.height + extra), bandHeight: m.height, gap: m.gap,
                              clockRect: clock, batteryRect: battery, slotRect: slot, artworkRect: artwork, playRect: play,
                              detailRect: detail, actionRect: action, controls: controls)
    }

    /// AppKit screen coordinates (bottom-left origin). Top-attached, horizontally centered on the display frame.
    public static func panelFrame(geometry g: IslandGeometry, displayFrame: CGRect, topOffset: CGFloat, scale: CGFloat) -> CGRect {
        let s = max(scale, 1)
        func snap(_ v: CGFloat) -> CGFloat { (v * s).rounded() / s }
        let x = snap(displayFrame.midX - g.size.width / 2)
        let y = snap(displayFrame.maxY - topOffset - g.size.height)
        return CGRect(x: x, y: y, width: g.size.width, height: g.size.height)
    }

    public static func hit(_ p: CGPoint, geometry g: IslandGeometry, mode: IslandMode) -> HitTarget {
        guard CGRect(origin: .zero, size: g.size).contains(p) else { return .outside }
        if p.y >= g.bandHeight {
            guard let r = mode.region else { return .outside }
            if case .expanded = mode {
                if let hit = g.controls.first(where: { $0.rect.contains(p) }) { return .control(hit.control) }
                if g.actionRect.contains(p) { return .action(r) }
            }
            return .detail(r)
        }
        if g.playRect.contains(p) { return .compact }
        let hasBattery = g.batteryRect.width > 0
        let clockEnd = hasBattery ? (g.clockRect.maxX + g.batteryRect.minX) / 2 : g.clockRect.maxX + g.gap / 2
        if p.x < clockEnd { return .region(.clock) }
        if hasBattery && p.x < g.batteryRect.maxX + g.gap / 2 { return .region(.battery) }
        return .region(.spotify)
    }
}
