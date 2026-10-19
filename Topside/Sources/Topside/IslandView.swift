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
    @Published var adDateText = ""
    @Published var bsDateText = ""
    @Published var combinedDateText = ""
    @Published var keyboardFocusRect: CGRect?
    @Published var hoveredTarget: HitTarget = .outside
    var activateSpotifyControl: ((SpotifyControl) -> Void)?
    var activateDateCopy: ((DateCopyControl) -> Void)?
    var activateRegionAction: ((Region) -> Void)?
}

struct BottomRoundedShape: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        let rad = min(radius, r.height / 2, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rad))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rad, y: r.maxY), radius: rad)
        p.addLine(to: CGPoint(x: r.minX + rad, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - rad), radius: rad)
        p.closeSubpath()
        return p
    }
}

struct BatteryGlyph: View {
    let display: BatteryDisplay

    private var fillColor: Color {
        if display.isCritical { return .red }
        if display.isLow || display.lowPowerMode { return .yellow }
        if display.status == .charging { return .green }
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

    func body(content: Content) -> some View {
        content.opacity(opacity).offset(y: y).scaleEffect(scale, anchor: .top)
    }
}

private extension AnyTransition {
    static var islandReveal: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandRevealModifier(opacity: 0, y: -5, scale: 0.985),
                identity: IslandRevealModifier(opacity: 1, y: 0, scale: 1)
            ),
            removal: .modifier(
                active: IslandRevealModifier(opacity: 0, y: -3, scale: 0.992),
                identity: IslandRevealModifier(opacity: 1, y: 0, scale: 1)
            )
        )
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandModel
    private let ink = Color(red: 5.0 / 255, green: 5.0 / 255, blue: 6.0 / 255)   // Obsidian #050506

    var body: some View {
        let g = model.geometry
        let pad = model.metrics.horizontalPadding
        ZStack(alignment: .topLeading) {
            BottomRoundedShape(radius: model.metrics.cornerRadius).fill(ink)

            Text(model.clockText)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: g.clockRect.width, height: g.clockRect.height, alignment: .leading)
                .offset(x: g.clockRect.minX, y: g.clockRect.minY)
                .accessibilityLabel("Time \(model.clockText)")
                .contentTransition(.numericText())

            if !model.battery.isHidden {
                HStack(spacing: 6) {
                    BatteryGlyph(display: model.battery)
                    if model.battery.showsPercent, let pct = model.battery.percent {
                        Text("\(pct)%").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundColor(.white)
                    }
                }
                .frame(width: g.batteryRect.width, height: g.batteryRect.height, alignment: .leading)
                .offset(x: g.batteryRect.minX, y: g.batteryRect.minY)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(model.battery.accessibilityLabel)
            }

            compactSlot(g)

            if g.detailRect.height > 0 {
                ZStack(alignment: .topLeading) {
                    Text(model.detailText)
                        .font(.system(size: 12))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .frame(width: max(0, g.size.width - pad * 2), height: 20, alignment: .leading)
                        .offset(x: pad, y: g.bandHeight + 5)
                        .contentTransition(.opacity)
                    if !model.detailSubtext.isEmpty {
                        Text(model.detailSubtext)
                            .font(.system(size: 11))
                            .foregroundColor(Color.white.opacity(0.55))
                            .lineLimit(1)
                            .frame(width: max(0, g.size.width - pad * 2), height: 16, alignment: .leading)
                            .offset(x: pad, y: g.bandHeight + 25)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    ForEach(Array(g.controls.enumerated()), id: \.offset) { item in
                        controlButton(item.element.control, compact: g.controls.count > 1)
                            .frame(width: item.element.rect.width, height: item.element.rect.height)
                            .offset(x: item.element.rect.minX, y: item.element.rect.minY)
                    }
                    ForEach(Array(g.dateControls.enumerated()), id: \.offset) { item in
                        let target = HitTarget.dateCopy(item.element.control)
                        Button(item.element.control.title) {
                            model.activateDateCopy?(item.element.control)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: item.element.rect.width, height: item.element.rect.height)
                        .background(buttonSurface(for: target))
                        .scaleEffect(model.hoveredTarget == target ? 1.025 : 1)
                        .offset(x: item.element.rect.minX, y: item.element.rect.minY)
                        .animation(.easeOut(duration: 0.12), value: model.hoveredTarget == target)
                        .accessibilityLabel(item.element.control.title)
                    }
                    if g.actionRect.height > 0, let region = model.mode.region {
                        let target = HitTarget.action(region)
                        Button(model.actionTitle) {
                            model.activateRegionAction?(region)
                        }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: g.actionRect.width, height: g.actionRect.height)
                            .background(buttonSurface(for: target))
                            .scaleEffect(model.hoveredTarget == target ? 1.018 : 1)
                            .offset(x: g.actionRect.minX, y: g.actionRect.minY)
                            .animation(.easeOut(duration: 0.12), value: model.hoveredTarget == target)
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
                .transition(.islandReveal)
            }
            if let focus = model.keyboardFocusRect {
                RoundedRectangle(cornerRadius: 9)
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

    // MARK: Spotify

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

    private func controlButton(_ control: SpotifyControl, compact: Bool) -> some View {
        let target = HitTarget.control(control)
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
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(buttonSurface(for: target))
        .scaleEffect(model.hoveredTarget == target ? 1.025 : 1)
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.12), value: model.hoveredTarget == target)
        .accessibilityLabel(control.buttonTitle)
    }

    private func buttonSurface(for target: HitTarget) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(model.hoveredTarget == target ? 0.2 : 0.12))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(model.hoveredTarget == target ? 0.13 : 0), lineWidth: 0.75)
            }
    }
}
