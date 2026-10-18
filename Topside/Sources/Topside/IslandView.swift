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
                }
                if display.status == .charging {
                    Image(systemName: "bolt.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.black.opacity(0.85))
                } else if display.status == .pluggedNotCharging {
                    Image(systemName: "powerplug.fill").font(.system(size: 7, weight: .bold)).foregroundColor(.black.opacity(0.85))
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.55)).frame(width: 2, height: 4)
        }
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
                Text(model.detailText)
                    .font(.system(size: 12))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(width: max(0, g.size.width - pad * 2), height: 20, alignment: .leading)
                    .offset(x: pad, y: g.bandHeight + 5)
                    .transition(.opacity)
                if !model.detailSubtext.isEmpty {
                    Text(model.detailSubtext)
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .frame(width: max(0, g.size.width - pad * 2), height: 16, alignment: .leading)
                        .offset(x: pad, y: g.bandHeight + 25)
                        .transition(.opacity)
                }
                ForEach(Array(g.controls.enumerated()), id: \.offset) { item in
                    controlButton(item.element.control, compact: g.controls.count > 1)
                        .frame(width: item.element.rect.width, height: item.element.rect.height)
                        .offset(x: item.element.rect.minX, y: item.element.rect.minY)
                        .transition(.opacity)
                }
                if g.actionRect.height > 0 {
                    Text(model.actionTitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: g.actionRect.width, height: g.actionRect.height)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
                        .offset(x: g.actionRect.minX, y: g.actionRect.minY)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Reduce Motion: no animation at all (instant); otherwise a short fade for panel content.
        .animation(model.reduceMotion ? nil : .easeOut(duration: 0.15), value: model.mode)
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
        Image(systemName: failed ? "exclamationmark.triangle.fill" : symbol(for: d.compactIcon))
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(failed ? .yellow : .white)
            .frame(width: g.playRect.width, height: g.playRect.height)
            .background(Circle().fill(Color.white.opacity(d.compactControl == nil ? 0 : 0.14)))
            .opacity(d.compactControl == nil && !failed ? 0.45 : 1)
            .offset(x: g.playRect.minX, y: g.playRect.minY)
            .accessibilityLabel(d.compactControl?.buttonTitle ?? d.detail)
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
        Group {
            switch control {
            case .previous: Image(systemName: "backward.fill")
            case .next: Image(systemName: "forward.fill")
            case .playPause: Image(systemName: model.spotify.availability == .playing ? "pause.fill" : "play.fill")
            case .open where compact: Image(systemName: "arrow.up.right.square")
            case .open, .connect, .openPrivacySettings: Text(control.buttonTitle).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.12)))
        .accessibilityLabel(control.buttonTitle)
    }
}
