import Foundation

/// Plain RGB (0...1). Free of AppKit/SwiftUI so the colour maths can be unit-tested.
public struct TintColor: Equatable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
}

/// Album-artwork tint, modelled on the Docky Spotify widget: the plain average colour of the artwork,
/// scaled down and lifted by a small floor, so white text always stays readable.
///
///     background = average * 0.36 + 0.04        (per channel)
public enum ArtworkTint {
    /// The island's resting colour (Obsidian #050506).
    public static let ink = TintColor(r: 5.0 / 255, g: 5.0 / 255, b: 6.0 / 255)

    public static let backgroundScale = 0.36
    public static let backgroundFloor = 0.04

    /// Alpha-weighted average colour of 8-bit RGBA pixels (row-major, premultiplied, as produced by a
    /// `CGContext` with `premultipliedLast`). Returns nil when the buffer is unusable or fully transparent,
    /// in which case callers stay neutral.
    public static func average(rgba: [UInt8], width: Int, height: Int) -> TintColor? {
        let count = width * height
        guard width > 0, height > 0, rgba.count >= count * 4 else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0
        for i in 0..<count {
            r += Double(rgba[i * 4]); g += Double(rgba[i * 4 + 1]); b += Double(rgba[i * 4 + 2])
            a += Double(rgba[i * 4 + 3])
        }
        guard a > 0 else { return nil }
        // Premultiplied sums divided by total alpha = alpha-weighted straight colour.
        return TintColor(r: min(1, r / a), g: min(1, g / a), b: min(1, b / a))
    }

    /// The dark, muted surface colour derived from an artwork average.
    public static func background(average a: TintColor) -> TintColor {
        TintColor(r: clamp(a.r * backgroundScale + backgroundFloor),
                  g: clamp(a.g * backgroundScale + backgroundFloor),
                  b: clamp(a.b * backgroundScale + backgroundFloor))
    }

    /// A light version of the artwork colour for small accents (progress fill, hover highlight):
    /// lifted toward white and never darker than 60% brightness, so it reads on the dark surface.
    public static func accent(average a: TintColor) -> TintColor {
        let lifted = TintColor(r: a.r + (1 - a.r) * 0.35, g: a.g + (1 - a.g) * 0.35, b: a.b + (1 - a.b) * 0.35)
        let v = max(lifted.r, lifted.g, lifted.b)
        guard v > 0 else { return TintColor(r: 0.6, g: 0.6, b: 0.6) }
        let k = v < 0.6 ? 0.6 / v : 1
        return TintColor(r: clamp(lifted.r * k), g: clamp(lifted.g * k), b: clamp(lifted.b * k))
    }

    /// Blend from the neutral ink toward `tint`. `amount` 0 = ink, 1 = fully tinted.
    public static func surface(tint: TintColor?, amount: Double) -> TintColor {
        guard let tint else { return ink }
        let t = clamp(amount)
        return TintColor(r: ink.r + (tint.r - ink.r) * t,
                         g: ink.g + (tint.g - ink.g) * t,
                         b: ink.b + (tint.b - ink.b) * t)
    }

    static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

/// How strongly each island state shows the tint, grain and hairline.
/// The collapsed island is always pure ink so it blends with the notch.
public enum IslandSurface {
    /// Tint share outside the player is faint; the pinned player gets the full tint.
    public static let faintTint = 0.35
    /// Peak opacity of the grain layer at strength 1.
    public static let grainMaxOpacity = 0.16

    public static func tintAmount(mode: IslandMode, showsPlayer: Bool, strength: Double) -> Double {
        let s = ArtworkTint.clamp(strength)
        switch mode {
        case .collapsed: return 0
        case .peek, .transient: return faintTint * s
        case .expanded: return (showsPlayer ? 1 : faintTint) * s
        }
    }

    public static func grainOpacity(mode: IslandMode, strength: Double) -> Double {
        let s = ArtworkTint.clamp(strength)
        switch mode {
        case .collapsed: return 0
        case .peek, .transient: return grainMaxOpacity * s * 0.5
        case .expanded: return grainMaxOpacity * s
        }
    }

    public static func hairlineOpacity(mode: IslandMode) -> Double {
        switch mode {
        case .collapsed: return 0
        case .peek, .transient: return 0.6
        case .expanded: return 1
        }
    }
}

/// WCAG contrast helpers for white text over the (possibly tinted) surface.
public enum Contrast {
    static func linear(_ c: Double) -> Double {
        c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    public static func luminance(_ c: TintColor) -> Double {
        0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    public static func ratio(_ a: TintColor, _ b: TintColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Smallest opacity >= `base` at which white text over `surface` reaches `minimum` contrast
    /// (capped at 1). Dark surfaces keep `base` unchanged; only bright tints raise it.
    public static func whiteTextOpacity(base: Double, minimum: Double, over surface: TintColor) -> Double {
        var alpha = min(max(base, 0), 1)
        while alpha < 1 {
            let blended = TintColor(r: surface.r + (1 - surface.r) * alpha,
                                    g: surface.g + (1 - surface.g) * alpha,
                                    b: surface.b + (1 - surface.b) * alpha)
            if ratio(blended, surface) >= minimum { return alpha }
            alpha += 0.01
        }
        return 1
    }
}

/// Deterministic film-grain tile: premultiplied white pixels with random alpha.
/// The same seed always yields the same bytes, so the texture never shimmers between launches.
public enum GrainNoise {
    public static let defaultSeed: UInt64 = 0x544F_5053_4944_45

    /// RGBA, row-major, `side * side * 4` bytes. Colour channels equal alpha (premultiplied white).
    public static func pixels(side: Int, seed: UInt64 = defaultSeed) -> [UInt8] {
        guard side > 0 else { return [] }
        var state = seed
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in 0..<(side * side) {
            // SplitMix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            let u = Double(z >> 11) / Double(1 << 53)          // 0..<1
            let a = UInt8(min(255, max(0, u * u * 255)))         // skewed low: mostly faint, a few bright specks
            bytes[i * 4] = a; bytes[i * 4 + 1] = a; bytes[i * 4 + 2] = a; bytes[i * 4 + 3] = a
        }
        return bytes
    }
}
