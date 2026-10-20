import AppKit
import SwiftUI
import TopsideCore

final class IslandModel: ObservableObject {
    @Published var clockText = ""
    @Published var battery = BatteryMapper.map(.unknown)
    @Published var mode: IslandMode = .collapsed
    @Published var geometry = IslandGeometry.empty
    @Published var metrics = IslandMetrics()
    @Published var detailText = ""
    @Published var actionTitle = ""
    @Published var reduceMotion = false
    @Published var spotify = SpotifyMapper.map(SpotifySnapshot(.closed))
    @Published var artwork: NSImage?
    @Published var detailSubtext = ""
    /// Brief failure message for a Spotify command; also flips the compact icon to a warning.
    @Published var spotifyNotice: String?
    /// Shared short-lived activity text (power, media failure, later audio).
    @Published var transientText: String?
    @Published var wifi = WiFiMapper.map(.unknown)
    @Published var outputSymbol = "speaker.wave.2.fill"
    @Published var outputName = ""
    @Published var transientTone: AnnouncementTone = .neutral
    /// Bumped to play a single glyph pulse when the battery crosses a low threshold.
    @Published var batteryPulse = 0
    @Published var adDateText = ""
    @Published var bsDateText = ""
    @Published var combinedDateText = ""
    @Published var keyboardFocusRect: CGRect?
    @Published var hoveredTarget: HitTarget = .outside
    /// Last sampled playback position; the player extrapolates from `progressSampledAt` while playing.
    @Published var progress: PlaybackProgress?
    @Published var progressSampledAt = Date()
    /// Plain average colour of the current artwork; nil = neutral ink. The view derives surface/accent from it.
    @Published var artworkAverage: TintColor?
    @Published var tintEnabled = true
    @Published var tintStrength = 1.0
    @Published var grainEnabled = true
    @Published var grainStrength = 0.5
    @Published var reduceTransparency = false
    /// Which date segment just copied; shows "Copied" inline for a moment.
    @Published var copiedDateControl: DateCopyControl?
    @Published var dateWeekday = ""
    @Published var dateDetailLine = ""
    var activateSpotifyControl: ((SpotifyControl) -> Void)?
    var activateDateCopy: ((DateCopyControl) -> Void)?
    var activateRegionAction: ((Region) -> Void)?
}

/// The island silhouette. Bottom corners are rounded; with `ear > 0` the top corners also flare
/// outward in a concave curve, so the island looks like it grows out of the top edge (notch style).
struct BottomRoundedShape: Shape {
    var radius: CGFloat
    var ear: CGFloat = 0

    func path(in r: CGRect) -> Path {
        let e = ear > 0 ? min(ear, r.width / 4, r.height / 2) : 0
        let bodyMinX = r.minX + e
        let bodyMaxX = r.maxX - e
        let rad = min(radius, r.height / 2, (bodyMaxX - bodyMinX) / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        if e > 0 {
            // Concave flare: centre (maxX, minY + e) carves the wallpaper-coloured quarter disc.
            p.addArc(tangent1End: CGPoint(x: bodyMaxX, y: r.minY), tangent2End: CGPoint(x: bodyMaxX, y: r.minY + e), radius: e)
        }
        p.addLine(to: CGPoint(x: bodyMaxX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: bodyMaxX, y: r.maxY), tangent2End: CGPoint(x: bodyMaxX - rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: bodyMinX + rad, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: bodyMinX, y: r.maxY), tangent2End: CGPoint(x: bodyMinX, y: r.maxY - rad), radius: rad)
        if e > 0 {
            p.addLine(to: CGPoint(x: bodyMinX, y: r.minY + e))
            p.addArc(tangent1End: CGPoint(x: bodyMinX, y: r.minY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: e)
        }
        p.closeSubpath()
        return p
    }
}

private struct MarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// One line of text that scrolls horizontally, with a pause at each end, only when it does not fit.
/// Give it `.id(text)` so a new string restarts the scroll. When it does not scroll (motion reduced or
/// `animates == false`) a long line fades out at the trailing edge instead of showing an ellipsis.
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let animates: Bool

    @State private var textWidth: CGFloat = 0
    @State private var startedAt = Date()

    private let speed: CGFloat = 28          // points per second
    private let pause: TimeInterval = 1.6    // hold at each end

    private var overflow: CGFloat { max(0, textWidth - width) }
    private var overflows: Bool { overflow > 0.5 }
    private var isScrolling: Bool { animates && overflows }

    var body: some View {
        ZStack(alignment: .leading) {
            // Invisible, unconstrained copy used only to measure the natural width.
            Text(text).font(font).lineLimit(1).fixedSize().opacity(0)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: proxy.size.width)
                })
            if isScrolling {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    label.fixedSize().offset(x: -scrollOffset(at: context.date))
                }
            } else {
                label.fixedSize()
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .clipped()
        .mask(fade)
        .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text).font(font).foregroundColor(color).lineLimit(1)
    }

    /// Soft fade on the trailing edge whenever the text is cut off, so it reads as "more to come".
    private var fade: LinearGradient {
        LinearGradient(stops: [.init(color: .black, location: 0),
                               .init(color: .black, location: overflows ? 0.88 : 1),
                               .init(color: overflows ? .clear : .black, location: 1)],
                       startPoint: .leading, endPoint: .trailing)
    }

    private func scrollOffset(at date: Date) -> CGFloat {
        let travel = overflow + 6
        let run = TimeInterval(travel / speed)
        let cycle = pause + run + pause
        let t = date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: cycle)
        if t < pause { return 0 }
        if t < pause + run { return CGFloat(t - pause) * speed }
        return travel
    }
}

struct WiFiGlyph: View {
    let display: WiFiDisplay

    var body: some View {
        Image(systemName: display.symbol, variableValue: display.variableValue)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color.white.opacity(display.state == .connected ? 0.9 : 0.5))
            .accessibilityLabel(display.accessibilityLabel)
    }
}

struct BatteryGlyph: View {
    let display: BatteryDisplay

    private var fillColor: Color {
        if display.isCritical { return .red }
        if display.isLow || display.lowPowerMode { return .yellow }
        // macOS reports "on AC" a few seconds before "charging"; show plugged-in as green straight away.
        if display.status == .charging || display.status == .pluggedNotCharging { return .green }
        return Color.white.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.55), lineWidth: 1).frame(width: 20, height: 10)
                if display.status != .unknown {
                    RoundedRectangle(cornerRadius: 1.5).fill(fillColor)
                        .frame(width: max(2, 16 * display.fillFraction), height: 6)
                        .frame(width: 16, height: 6, alignment: .leading)
                        .animation(.spring(response: 0.28, dampingFraction: 0.9), value: display.fillFraction)
                }
                if display.status == .charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.black.opacity(0.85))
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                } else if display.status == .pluggedNotCharging {
                    Image(systemName: "powerplug.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.black.opacity(0.85))
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.55)).frame(width: 2, height: 4)
        }
        .animation(.easeOut(duration: 0.16), value: display.status)
    }
}

private struct IslandRevealModifier: ViewModifier {
    let opacity: Double
    let y: CGFloat
    let scale: CGFloat
    var blur: CGFloat = 0

    func body(content: Content) -> some View {
        content.opacity(opacity).blur(radius: blur).offset(y: y).scaleEffect(scale, anchor: .top)
    }
}

private extension AnyTransition {
    /// Detail content waits until the shape is roughly 30-50% open before fading in (the panel's grow
    /// animation takes 0.20 s), and leaves quickly before it closes, so content never rides the resize.
    static var islandReveal: AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(
                active: IslandRevealModifier(opacity: 0, y: -5, scale: 0.985, blur: 5),
                identity: IslandRevealModifier(opacity: 1, y: 0, scale: 1)
            ).animation(.easeOut(duration: 0.16).delay(0.04)),
            removal: AnyTransition.modifier(
                active: IslandRevealModifier(opacity: 0, y: -3, scale: 0.992, blur: 3),
                identity: IslandRevealModifier(opacity: 1, y: 0, scale: 1)
            ).animation(.easeIn(duration: 0.10))
        )
    }

    /// A new track title slides in a few points with a blur-fade; the old one simply fades out.
    static var titleSwap: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: IslandRevealModifier(opacity: 0, y: 4, scale: 1, blur: 4),
                                 identity: IslandRevealModifier(opacity: 1, y: 0, scale: 1)),
            removal: .opacity
        )
    }
}

private extension Color {
    init(_ tint: TintColor) { self.init(red: tint.r, green: tint.g, blue: tint.b) }
}

/// Deterministic film-grain tile (see `GrainNoise`). Built once; drawn tiled at 2x so each noise pixel is a device pixel.
enum GrainTexture {
    static let image: CGImage? = {
        let side = 128
        let bytes = GrainNoise.pixels(side: side)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    @State private var batteryPulsing = false

    private var showsPlayer: Bool { model.geometry.player != nil }

    /// Surface colour for the current state: ink when collapsed, blending toward the album tint as it opens.
    private var surface: TintColor {
        let amount = model.tintEnabled
            ? IslandSurface.tintAmount(mode: model.mode, showsPlayer: showsPlayer, strength: model.tintStrength)
            : 0
        return ArtworkTint.surface(tint: model.artworkAverage.map { ArtworkTint.background(average: $0) }, amount: amount)
    }

    /// Light album colour for the progress fill and hover highlights; plain white without artwork.
    private var accent: Color {
        guard model.tintEnabled, let average = model.artworkAverage else { return Color.white.opacity(0.85) }
        return Color(ArtworkTint.accent(average: average))
    }

    var body: some View {
        let g = model.geometry
        let s = surface
        // Text opacities rise only as far as needed to keep contrast on bright tints.
        let secondary = Contrast.whiteTextOpacity(base: 0.55, minimum: 4.5, over: s)      // 11.5 pt secondary
        let tertiary = Contrast.whiteTextOpacity(base: 0.40, minimum: 3.0, over: s)       // 10 pt tertiary
        let shape = BottomRoundedShape(radius: model.metrics.cornerRadius, ear: g.ear)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(s))
                .animation(model.reduceMotion ? nil : .easeInOut(duration: 0.4), value: s)
            grainLayer(shape)
            hairline(shape)

            Text(model.clockText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: g.clockRect.width, height: g.clockRect.height, alignment: .leading)
                .offset(x: g.clockRect.minX, y: g.clockRect.minY)
                .accessibilityLabel("Time \(model.clockText)")
                .contentTransition(.numericText())

            if !model.battery.isHidden {
                if g.wifiRect.width > 0 {
                    WiFiGlyph(display: model.wifi)
                        .frame(width: g.wifiRect.width, height: g.wifiRect.height)
                        .offset(x: g.wifiRect.minX, y: g.wifiRect.minY)
                }
                HStack(spacing: 8) {
                    BatteryGlyph(display: model.battery)
                    if model.battery.showsPercent, let pct = model.battery.percent {
                        Text("\(pct)%").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(.white)
                            .contentTransition(.numericText())
                            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.25), value: pct)
                    }
                }
                .scaleEffect(batteryPulsing ? 1.14 : 1, anchor: .leading)
                .onChange(of: model.batteryPulse) { _ in pulseBattery() }
                .frame(width: g.batteryRect.width - wifiShift(g), height: g.batteryRect.height, alignment: .leading)
                .offset(x: g.batteryRect.minX + wifiShift(g), y: g.batteryRect.minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.battery.accessibilityLabel)
            }

            // The pinned player has its own artwork and play control, so the compact ones fade out.
            Group { compactSlot(g) }
                .opacity(g.player == nil ? 1 : 0)
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.14), value: g.player == nil)

            if g.detailRect.height > 0 {
                ZStack(alignment: .topLeading) {
                    if let player = g.player {
                        playerContent(player, secondary: secondary, tertiary: tertiary)
                    } else {
                        detailTexts(g, secondary: secondary)
                    }
                    ForEach(Array(g.controls.enumerated()), id: \.offset) { item in
                        if g.player != nil {
                            playerControl(item.element.control, rect: item.element.rect)
                        } else {
                            fallbackControl(item.element.control, compact: g.controls.count > 1)
                                .frame(width: item.element.rect.width, height: item.element.rect.height)
                                .offset(x: item.element.rect.minX, y: item.element.rect.minY)
                        }
                    }
                    dateCapsule(g)
                    batteryLink(g)
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .transition(model.reduceMotion ? .opacity : .islandReveal)
            }
            if let focus = model.keyboardFocusRect {
                RoundedRectangle(cornerRadius: min(focus.width, focus.height) / 2)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: focus.width, height: focus.height)
                    .offset(x: focus.minX, y: focus.minY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .animation(.spring(response: 0.24, dampingFraction: 0.88), value: focus)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(model.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.9), value: model.mode)
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.16), value: model.detailText)
    }

    // MARK: Surface layers

    /// Subtle film grain, clipped to the island. Zero when collapsed, fading in as the island opens.
    @ViewBuilder private func grainLayer(_ shape: BottomRoundedShape) -> some View {
        if model.grainEnabled, !model.reduceTransparency, let tile = GrainTexture.image {
            Image(decorative: tile, scale: 2)
                .resizable(resizingMode: .tile)
                .opacity(IslandSurface.grainOpacity(mode: model.mode, strength: model.grainStrength))
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 0.5 pt inner hairline: invisible along the flush top edge, strongest near the upper sides, fading downward.
    private func hairline(_ shape: BottomRoundedShape) -> some View {
        shape
            .stroke(LinearGradient(stops: [.init(color: Color.white.opacity(0), location: 0),
                                           .init(color: Color.white.opacity(0.10), location: 0.22),
                                           .init(color: Color.white.opacity(0.03), location: 1)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            .clipShape(shape)                 // clipping halves the centred stroke: 0.5 pt inside the edge
            .opacity(IslandSurface.hairlineOpacity(mode: model.mode))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The battery glyph starts after the Wi-Fi icon when one is shown.
    private func wifiShift(_ g: IslandGeometry) -> CGFloat {
        g.wifiRect.width > 0 ? g.wifiRect.width + IslandLayout.wifiIconGap : 0
    }

    // MARK: Detail text (peek, date, battery)

    /// Warm text for a low-battery cue; everything else stays white.
    private var detailColor: Color {
        guard case .transient = model.mode else { return .white }
        switch model.transientTone {
        case .neutral: return .white
        case .warning: return Color(red: 1.0, green: 0.80, blue: 0.35)
        case .critical: return Color(red: 1.0, green: 0.45, blue: 0.40)
        }
    }

    private func pulseBattery() {
        guard !model.reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.16)) { batteryPulsing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { batteryPulsing = false }
        }
    }

    @ViewBuilder private func detailTexts(_ g: IslandGeometry, secondary: Double) -> some View {
        if case .expanded(.battery) = model.mode {
            Text(model.battery.headline)
                .font(.system(size: 24, weight: .semibold).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(model.reduceMotion ? nil : .easeOut(duration: 0.25), value: model.battery.percent)
                .frame(width: g.primaryRect.width, height: g.primaryRect.height, alignment: .leading)
                .offset(x: g.primaryRect.minX, y: g.primaryRect.minY)
            MarqueeText(text: model.battery.statusLine, font: .system(size: 11.5), color: Color.white.opacity(secondary),
                        width: g.secondaryRect.width, height: g.secondaryRect.height, animates: false)
                .offset(x: g.secondaryRect.minX, y: g.secondaryRect.minY)
        } else {
            MarqueeText(text: model.detailText, font: .system(size: 13, weight: .semibold), color: detailColor,
                        width: g.primaryRect.width, height: g.primaryRect.height, animates: false)
                .offset(x: g.primaryRect.minX, y: g.primaryRect.minY)
            if !model.detailSubtext.isEmpty {
                MarqueeText(text: model.detailSubtext, font: .system(size: 11.5).monospacedDigit(),
                            color: Color.white.opacity(secondary),
                            width: g.secondaryRect.width, height: g.secondaryRect.height, animates: false)
                    .offset(x: g.secondaryRect.minX, y: g.secondaryRect.minY)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: Date: one segmented capsule

    @ViewBuilder private func dateCapsule(_ g: IslandGeometry) -> some View {
        if let first = g.dateControls.first, let last = g.dateControls.last {
            let box = CGRect(x: first.rect.minX, y: first.rect.minY,
                             width: last.rect.maxX - first.rect.minX, height: first.rect.height)
            ZStack(alignment: .topLeading) {
                ForEach(Array(g.dateControls.enumerated()), id: \.offset) { item in
                    dateSegment(item.element.control)
                        .frame(width: item.element.rect.width, height: item.element.rect.height)
                        .offset(x: item.element.rect.minX - box.minX, y: 0)
                }
                ForEach(1..<max(1, g.dateControls.count), id: \.self) { i in
                    Rectangle().fill(Color.white.opacity(0.14))
                        .frame(width: 0.5, height: box.height - 12)
                        .offset(x: g.dateControls[i].rect.minX - box.minX - 0.25, y: 6)
                }
            }
            .frame(width: box.width, height: box.height, alignment: .topLeading)
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5))
            .offset(x: box.minX, y: box.minY)
        }
    }

    private func dateSegment(_ control: DateCopyControl) -> some View {
        let hovered = model.hoveredTarget == .dateCopy(control)
        let copied = model.copiedDateControl == control
        return Button { model.activateDateCopy?(control) } label: {
            ZStack {
                Rectangle().fill(Color.white.opacity(hovered ? 0.10 : 0))
                Group {
                    if copied {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            Text("Copied")
                        }
                        .transition(.opacity)
                    } else {
                        Text(control.shortTitle).transition(.opacity)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color.white.opacity(hovered || copied ? 1 : 0.75))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .animation(model.reduceMotion ? nil : .easeInOut(duration: 0.18), value: copied)
        .accessibilityLabel(copied ? "Copied" : control.title)
    }

    // MARK: Battery settings link

    @ViewBuilder private func batteryLink(_ g: IslandGeometry) -> some View {
        if g.actionRect.height > 0, let region = model.mode.region {
            let hovered = model.hoveredTarget == .action(region)
            Button { model.activateRegionAction?(region) } label: {
                HStack(spacing: 3) {
                    Text(model.actionTitle)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(Color.white.opacity(hovered ? 1 : 0.7))
                .frame(width: g.actionRect.width, height: g.actionRect.height, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .offset(x: g.actionRect.minX, y: g.actionRect.minY)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .accessibilityLabel(model.actionTitle)
        }
    }

    // MARK: Pinned Spotify player

    @ViewBuilder private func playerContent(_ p: SpotifyPlayerRects, secondary: Double, tertiary: Double) -> some View {
        largeArtwork
            .frame(width: p.artworkRect.width, height: p.artworkRect.height)
            .offset(x: p.artworkRect.minX, y: p.artworkRect.minY)
        MarqueeText(text: model.detailText, font: .system(size: 13, weight: .semibold), color: .white,
                    width: p.titleRect.width, height: p.titleRect.height, animates: !model.reduceMotion)
            .id(model.detailText)
            .transition(model.reduceMotion ? .opacity : .titleSwap)
            .offset(x: p.titleRect.minX, y: p.titleRect.minY)
        if !model.detailSubtext.isEmpty {
            MarqueeText(text: model.detailSubtext, font: .system(size: 11.5), color: Color.white.opacity(secondary),
                        width: p.subtitleRect.width, height: p.subtitleRect.height, animates: false)
                .offset(x: p.subtitleRect.minX, y: p.subtitleRect.minY)
        }
        if p.barRect.width > 0 { progressRow(p, tertiary: tertiary) }
        outputChip(model.geometry.outputRect)
    }

    /// Headphones when personal audio is connected, a speaker otherwise. Click opens the output menu.
    @ViewBuilder private func outputChip(_ rect: CGRect) -> some View {
        if rect.width > 0 {
            let hovered = model.hoveredTarget == .audioOutput
            ZStack {
                Circle().fill(accent.opacity(hovered ? 0.28 : 0)).frame(width: 28, height: 28)
                Image(systemName: model.outputSymbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(hovered ? 1 : 0.72))
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sound output: \(model.outputName). Choose output")
        }
    }

    private var largeArtwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.14))
            if let image = model.artwork {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.system(size: 18)).foregroundColor(Color.white.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // Edge definition so dark covers don't dissolve into the tinted surface.
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 2)
        .opacity(model.spotify.isPaused ? 0.65 : 1)
        .animation(model.reduceMotion ? nil : .easeInOut(duration: 0.3), value: model.artwork != nil)
        .accessibilityHidden(true)
    }

    private func progressRow(_ p: SpotifyPlayerRects, tertiary: Double) -> some View {
        TimelineView(.periodic(from: Date(), by: 0.5)) { context in
            let playing = model.spotify.availability == .playing
            let sinceSample = context.date.timeIntervalSince(model.progressSampledAt)
            let position = model.progress?.position(afterSampleBy: sinceSample, isPlaying: playing) ?? 0
            let fraction = model.progress?.fraction(afterSampleBy: sinceSample, isPlaying: playing) ?? 0
            let elapsedText = PlaybackProgress.label(for: position)
            let totalText = PlaybackProgress.label(for: model.progress?.duration ?? 0)
            ZStack(alignment: .topLeading) {
                Text(elapsedText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.white.opacity(tertiary))
                    .frame(width: p.elapsedRect.width, height: p.elapsedRect.height, alignment: .leading)
                    .offset(x: p.elapsedRect.minX, y: p.elapsedRect.minY)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(accent).frame(width: max(0, p.barRect.width * CGFloat(fraction)))
                }
                .frame(width: p.barRect.width, height: p.barRect.height)
                .offset(x: p.barRect.minX, y: p.barRect.minY)
                .animation(model.reduceMotion ? nil : .linear(duration: 0.5), value: fraction)
                Text(totalText)
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(Color.white.opacity(tertiary))
                    .frame(width: p.durationRect.width, height: p.durationRect.height, alignment: .trailing)
                    .offset(x: p.durationRect.minX, y: p.durationRect.minY)
            }
            .frame(width: model.geometry.size.width, height: model.geometry.size.height, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(elapsedText) of \(totalText)")
        }
    }

    /// Icon-only transport: quiet previous/next, a solid white play/pause circle, a small "open" icon.
    private func playerControl(_ control: SpotifyControl, rect: CGRect) -> some View {
        let hovered = model.hoveredTarget == .control(control)
        let playing = model.spotify.availability == .playing
        return Button { model.activateSpotifyControl?(control) } label: {
            ZStack {
                switch control {
                case .playPause:
                    Circle().fill(Color.white.opacity(hovered ? 1 : 0.92))
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color.black.opacity(0.85))
                case .previous, .next:
                    Circle().fill(accent.opacity(hovered ? 0.28 : 0)).frame(width: 32, height: 32)
                    Image(systemName: control == .previous ? "backward.fill" : "forward.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(hovered ? 1 : 0.72))
                case .open:
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.white.opacity(hovered ? 1 : 0.6))
                case .connect, .openPrivacySettings:
                    EmptyView()
                }
            }
            .frame(width: rect.width, height: rect.height)
        }
        .buttonStyle(.plain)
        .scaleEffect(hovered && control != .open ? 1.04 : 1)
        .offset(x: rect.minX, y: rect.minY)
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(control.buttonTitle)
    }

    /// States without a track (closed, idle, permission): one quiet outlined capsule, no resting fill.
    private func fallbackControl(_ control: SpotifyControl, compact: Bool) -> some View {
        let hovered = model.hoveredTarget == .control(control)
        return Button { model.activateSpotifyControl?(control) } label: {
            Group {
                switch control {
                case .previous: Image(systemName: "backward.fill")
                case .next: Image(systemName: "forward.fill")
                case .playPause: Image(systemName: model.spotify.availability == .playing ? "pause.fill" : "play.fill")
                case .open where compact: Image(systemName: "arrow.up.right.square")
                case .open, .connect, .openPrivacySettings: Text(control.buttonTitle).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Capsule().fill(Color.white.opacity(hovered ? 0.12 : 0)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(hovered ? 0.22 : 0.14), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(Color.white.opacity(hovered ? 1 : 0.85))
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        .accessibilityLabel(control.buttonTitle)
    }

    // MARK: Compact Spotify slot (collapsed band)

    @ViewBuilder private func compactSlot(_ g: IslandGeometry) -> some View {
        let d = model.spotify
        let failed = model.spotifyNotice != nil
        if d.showsArtwork {
            artworkView(d)
                .frame(width: g.artworkRect.width, height: g.artworkRect.height)
                .offset(x: g.artworkRect.minX, y: g.artworkRect.minY)
        }
        if let control = d.compactControl {
            Button { model.activateSpotifyControl?(control) } label: {
                compactIcon(d, failed: failed)
            }
            .buttonStyle(.plain)
            .offset(x: g.playRect.minX, y: g.playRect.minY)
            .accessibilityLabel(control.buttonTitle)
        } else {
            compactIcon(d, failed: failed)
                .offset(x: g.playRect.minX, y: g.playRect.minY)
                .accessibilityLabel(d.detail)
        }
    }

    private func compactIcon(_ d: SpotifyDisplay, failed: Bool) -> some View {
        let icon = failed ? "exclamationmark.triangle.fill" : symbol(for: d.compactIcon)
        let hovered = model.hoveredTarget == .compact
        return ZStack {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(failed ? .yellow : .white)
                .id(icon)
                .transition(.scale(scale: 0.72).combined(with: .opacity))
        }
            .frame(width: model.geometry.playRect.width, height: model.geometry.playRect.height)
            .background(Circle().fill(Color.white.opacity(d.compactControl == nil ? 0 : hovered ? 0.24 : 0.14)))
            .opacity(d.compactControl == nil && !failed ? 0.45 : 1)
            .scaleEffect(hovered ? 1.08 : 1)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .animation(model.reduceMotion ? nil : .easeOut(duration: 0.16), value: icon)
    }

    /// Compact artwork in the collapsed band. Playing vs paused is carried by the play/pause icon next to it
    /// and by the artwork dimming; there is no badge on top of the artwork.
    private func artworkView(_ d: SpotifyDisplay) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.14))
            if let image = model.artwork {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 10)).foregroundColor(Color.white.opacity(0.7))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .opacity(d.isPaused ? 0.55 : 1)
        .scaleEffect(model.hoveredTarget == .region(.spotify) ? 1.035 : 1)
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.16), value: model.hoveredTarget == .region(.spotify))
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.2), value: model.artwork != nil)
    }

    private func symbol(for icon: CompactIcon) -> String {
        switch icon {
        case .play: return "play.fill"
        case .pause: return "pause.fill"
        case .launch, .unavailable: return "music.note"
        case .connect: return "link"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}
