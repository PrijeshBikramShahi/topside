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

    public init(height: CGFloat = 36, topOffset: CGFloat = 0, minWidth: CGFloat = 184, maxWidth: CGFloat = 240,
                horizontalPadding: CGFloat = 14, gap: CGFloat = 10, slotWidth: CGFloat = 48,
                peekExtra: CGFloat = 30, expandedExtra: CGFloat = 66,
                datePeekExtra: CGFloat = 44, dateExpandedExtra: CGFloat = 84, cornerRadius: CGFloat = 18,
                spotifyExpandedExtra: CGFloat = 84, compactSize: CGFloat = 22) {
        self.height = height; self.topOffset = topOffset; self.minWidth = minWidth; self.maxWidth = maxWidth
        self.horizontalPadding = horizontalPadding; self.gap = gap; self.slotWidth = slotWidth
        self.peekExtra = peekExtra; self.expandedExtra = expandedExtra
        self.datePeekExtra = datePeekExtra; self.dateExpandedExtra = dateExpandedExtra; self.cornerRadius = cornerRadius
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
    public var dateControls: [DateControlRect]

    public init(size: CGSize, bandHeight: CGFloat, gap: CGFloat, clockRect: CGRect, batteryRect: CGRect,
                slotRect: CGRect, artworkRect: CGRect = .zero, playRect: CGRect = .zero,
                detailRect: CGRect, actionRect: CGRect, controls: [ControlRect] = [],
                dateControls: [DateControlRect] = []) {
        self.size = size; self.bandHeight = bandHeight; self.gap = gap; self.clockRect = clockRect
        self.batteryRect = batteryRect; self.slotRect = slotRect; self.artworkRect = artworkRect; self.playRect = playRect
        self.detailRect = detailRect; self.actionRect = actionRect; self.controls = controls
        self.dateControls = dateControls
    }

    public static let empty = IslandGeometry(size: .zero, bandHeight: 0, gap: 0, clockRect: .zero, batteryRect: .zero,
                                             slotRect: .zero, detailRect: .zero, actionRect: .zero)
}

public enum IslandLayout {
    /// The island is flush with the top of its window and only its bottom
    /// corners are rounded. Points outside those visible corners must pass
    /// through to the application underneath.
    public static func containsVisibleShape(_ p: CGPoint, size: CGSize, cornerRadius: CGFloat) -> Bool {
        let bounds = CGRect(origin: .zero, size: size)
        guard bounds.contains(p) else { return false }
        let radius = min(max(cornerRadius, 0), size.width / 2, size.height / 2)
        guard radius > 0, p.y > size.height - radius else { return true }

        if p.x < radius {
            let dx = p.x - radius
            let dy = p.y - (size.height - radius)
            return dx * dx + dy * dy <= radius * radius
        }
        if p.x > size.width - radius {
            let dx = p.x - (size.width - radius)
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
        let pad = m.horizontalPadding
        let hasBattery = c.batteryWidth > 0
        let natural = pad * 2 + c.clockWidth + (hasBattery ? m.gap + c.batteryWidth : 0) + m.gap + m.slotWidth
        let collapsedWidth = min(max(natural, m.minWidth), m.maxWidth)
        // Detail text and action labels need the full planned width; only the
        // resting island should hug its compact content.
        let width = mode == .collapsed ? collapsedWidth : m.maxWidth
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
        var dateControls: [DateControlRect] = []
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
            } else if region == .clock {
                let values = DateCopyControl.allCases
                let spacing: CGFloat = 6
                let w = (width - pad * 2 - spacing * CGFloat(values.count - 1)) / CGFloat(values.count)
                dateControls = values.enumerated().map { index, control in
                    DateControlRect(control: control,
                                    rect: CGRect(x: pad + CGFloat(index) * (w + spacing),
                                                 y: m.height + 52, width: w, height: 24))
                }
            } else {
                action = CGRect(x: pad, y: m.height + 30, width: width - pad * 2, height: 24)
            }
        }

        return IslandGeometry(size: CGSize(width: width, height: m.height + extra), bandHeight: m.height, gap: m.gap,
                              clockRect: clock, batteryRect: battery, slotRect: slot, artworkRect: artwork, playRect: play,
                              detailRect: detail, actionRect: action, controls: controls, dateControls: dateControls)
    }

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
        guard containsVisibleShape(p, size: g.size, cornerRadius: cornerRadius ?? g.bandHeight / 2) else { return .outside }
        if p.y >= g.bandHeight {
            guard let r = mode.region else { return .outside }
            if case .expanded = mode {
                if let hit = g.controls.first(where: { $0.rect.contains(p) }) { return .control(hit.control) }
                if let hit = g.dateControls.first(where: { $0.rect.contains(p) }) { return .dateCopy(hit.control) }
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
