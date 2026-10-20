import XCTest
@testable import TopsideCore

final class ArtworkTintTests: XCTestCase {
    /// Solid-colour premultiplied RGBA buffer.
    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8, a: UInt8 = 255, count: Int = 16) -> [UInt8] {
        let pr = UInt8(Double(r) * Double(a) / 255), pg = UInt8(Double(g) * Double(a) / 255), pb = UInt8(Double(b) * Double(a) / 255)
        return Array((0..<count).map { _ in [pr, pg, pb, a] }.joined())
    }

    private func rgb255(_ c: TintColor) -> (Double, Double, Double) { (c.r * 255, c.g * 255, c.b * 255) }

    // MARK: Average

    func testAverageOfSolidArtworkIsThatColour() throws {
        let avg = try XCTUnwrap(ArtworkTint.average(rgba: solid(200, 100, 50), width: 4, height: 4))
        XCTAssertEqual(avg.r, 200.0 / 255, accuracy: 0.002)
        XCTAssertEqual(avg.g, 100.0 / 255, accuracy: 0.002)
        XCTAssertEqual(avg.b, 50.0 / 255, accuracy: 0.002)
    }

    func testAverageIsAPlainMeanNotWeightedTowardColourfulPixels() throws {
        // Half pure red, half white: a saturation-weighted scheme would lean red; the plain mean does not.
        var px = solid(255, 0, 0, count: 8)
        px += solid(255, 255, 255, count: 8)
        let avg = try XCTUnwrap(ArtworkTint.average(rgba: px, width: 4, height: 4))
        XCTAssertEqual(avg.r, 1.0, accuracy: 0.002)
        XCTAssertEqual(avg.g, 0.5, accuracy: 0.004)
        XCTAssertEqual(avg.b, 0.5, accuracy: 0.004)
    }

    func testTransparentPixelsDoNotDarkenTheAverage() throws {
        var px = solid(200, 100, 50, count: 8)
        px += solid(0, 0, 0, a: 0, count: 8)
        let avg = try XCTUnwrap(ArtworkTint.average(rgba: px, width: 4, height: 4))
        XCTAssertEqual(avg.r, 200.0 / 255, accuracy: 0.004)
    }

    func testUnusableBuffersReturnNil() {
        XCTAssertNil(ArtworkTint.average(rgba: [], width: 0, height: 0))
        XCTAssertNil(ArtworkTint.average(rgba: [1, 2, 3], width: 4, height: 4))                 // too short
        XCTAssertNil(ArtworkTint.average(rgba: solid(10, 20, 30, a: 0), width: 4, height: 4))   // fully transparent
        XCTAssertNil(ArtworkTint.average(rgba: solid(10, 20, 30), width: 0, height: 4))
    }

    // MARK: Background formula (average * 0.36 + 0.04)

    func testBackgroundFormula() {
        let bg = ArtworkTint.background(average: TintColor(r: 200.0 / 255, g: 100.0 / 255, b: 50.0 / 255))
        XCTAssertEqual(bg.r, 200.0 / 255 * 0.36 + 0.04, accuracy: 1e-9)
        XCTAssertEqual(bg.g, 100.0 / 255 * 0.36 + 0.04, accuracy: 1e-9)
        XCTAssertEqual(bg.b, 50.0 / 255 * 0.36 + 0.04, accuracy: 1e-9)
    }

    func testBackgroundIsAlwaysDarkEnoughForWhiteText() {
        let white = ArtworkTint.background(average: TintColor(r: 1, g: 1, b: 1))
        XCTAssertEqual(white.r, 0.40, accuracy: 1e-9)
        let black = ArtworkTint.background(average: TintColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(black.r, 0.04, accuracy: 1e-9)
        // Plain white text on the brightest possible tint is still comfortably legible.
        XCTAssertGreaterThan(Contrast.ratio(TintColor(r: 1, g: 1, b: 1), white), 5)
    }

    /// The backgrounds measured from the reference widget's screenshots (within a few 8-bit steps:
    /// the screenshots are rounded, scaled and cropped).
    func testMatchesBackgroundsMeasuredFromTheReferenceWidget() {
        let cases: [(avg: (Double, Double, Double), bg: (Double, Double, Double))] = [
            ((173, 51, 104), (72, 26, 47)),     // Khone Do
            ((73, 71, 51), (37, 36, 28)),       // Hopes and Fears
            ((187, 141, 134), (78, 61, 59)),    // Speak Now
        ]
        for c in cases {
            let out = rgb255(ArtworkTint.background(average: TintColor(r: c.avg.0 / 255, g: c.avg.1 / 255, b: c.avg.2 / 255)))
            XCTAssertEqual(out.0, c.bg.0, accuracy: 4)
            XCTAssertEqual(out.1, c.bg.1, accuracy: 4)
            XCTAssertEqual(out.2, c.bg.2, accuracy: 4)
        }
    }

    func testBackgroundKeepsTheArtworkHue() {
        let pink = ArtworkTint.background(average: TintColor(r: 0.68, g: 0.20, b: 0.41))
        XCTAssertGreaterThan(pink.r, pink.b)
        XCTAssertGreaterThan(pink.b, pink.g)
    }

    // MARK: Accent

    func testAccentIsLightEvenForDarkArtwork() {
        let dark = ArtworkTint.accent(average: TintColor(r: 0.28, g: 0.27, b: 0.20))
        XCTAssertGreaterThanOrEqual(max(dark.r, dark.g, dark.b), 0.6 - 1e-9)
        let black = ArtworkTint.accent(average: TintColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(black, TintColor(r: 0.6, g: 0.6, b: 0.6))
    }

    func testAccentStaysInRange() {
        for avg in [TintColor(r: 1, g: 1, b: 1), TintColor(r: 1, g: 0, b: 0), TintColor(r: 0.1, g: 0.5, b: 0.9)] {
            let a = ArtworkTint.accent(average: avg)
            for v in [a.r, a.g, a.b] { XCTAssertTrue((0...1).contains(v)) }
        }
    }

    // MARK: Surface blend

    func testSurfaceBlendsFromInkTowardTheTint() {
        let tint = TintColor(r: 0.3, g: 0.1, b: 0.2)
        XCTAssertEqual(ArtworkTint.surface(tint: tint, amount: 0), ArtworkTint.ink)
        XCTAssertEqual(ArtworkTint.surface(tint: tint, amount: 1), tint)
        let half = ArtworkTint.surface(tint: tint, amount: 0.5)
        XCTAssertEqual(half.r, (ArtworkTint.ink.r + 0.3) / 2, accuracy: 1e-9)
    }

    func testSurfaceWithoutTintIsInkAndAmountIsClamped() {
        XCTAssertEqual(ArtworkTint.surface(tint: nil, amount: 1), ArtworkTint.ink)
        let tint = TintColor(r: 0.3, g: 0.1, b: 0.2)
        XCTAssertEqual(ArtworkTint.surface(tint: tint, amount: 5), tint)
        XCTAssertEqual(ArtworkTint.surface(tint: tint, amount: -2), ArtworkTint.ink)
    }

    func testInkIsObsidian() {
        XCTAssertEqual(ArtworkTint.ink.r, 5.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(ArtworkTint.ink.b, 6.0 / 255, accuracy: 1e-12)
    }
}

final class IslandSurfaceTests: XCTestCase {
    func testCollapsedIsPureInkWithNoGrainOrHairline() {
        XCTAssertEqual(IslandSurface.tintAmount(mode: .collapsed, showsPlayer: false, strength: 1), 0)
        XCTAssertEqual(IslandSurface.grainOpacity(mode: .collapsed, strength: 1), 0)
        XCTAssertEqual(IslandSurface.hairlineOpacity(mode: .collapsed), 0)
    }

    func testPlayerGetsFullTintAndOtherPinnedStatesGetAFaintOne() {
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.spotify), showsPlayer: true, strength: 1), 1)
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.clock), showsPlayer: false, strength: 1), IslandSurface.faintTint)
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.battery), showsPlayer: false, strength: 1), IslandSurface.faintTint)
        XCTAssertLessThan(IslandSurface.faintTint, 0.5)
    }

    func testPeekAndTransientAreFaint() {
        for mode in [IslandMode.peek(.spotify), .transient(.battery)] {
            XCTAssertEqual(IslandSurface.tintAmount(mode: mode, showsPlayer: false, strength: 1), IslandSurface.faintTint)
        }
    }

    func testStrengthScalesAndClamps() {
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.spotify), showsPlayer: true, strength: 0.5), 0.5)
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.spotify), showsPlayer: true, strength: 7), 1)
        XCTAssertEqual(IslandSurface.tintAmount(mode: .expanded(.spotify), showsPlayer: true, strength: -1), 0)
        XCTAssertEqual(IslandSurface.grainOpacity(mode: .expanded(.clock), strength: 0), 0)
    }

    func testGrainFadesInWithExpansion() {
        let peek = IslandSurface.grainOpacity(mode: .peek(.clock), strength: 1)
        let pinned = IslandSurface.grainOpacity(mode: .expanded(.clock), strength: 1)
        XCTAssertGreaterThan(peek, 0)
        XCTAssertGreaterThan(pinned, peek)
        XCTAssertEqual(pinned, IslandSurface.grainMaxOpacity)
    }
}

final class ContrastTests: XCTestCase {
    private let white = TintColor(r: 1, g: 1, b: 1)

    func testKnownRatios() {
        XCTAssertEqual(Contrast.ratio(white, TintColor(r: 0, g: 0, b: 0)), 21, accuracy: 0.01)
        XCTAssertEqual(Contrast.ratio(white, white), 1, accuracy: 0.0001)
    }

    func testDarkSurfaceKeepsTheBaseOpacity() {
        XCTAssertEqual(Contrast.whiteTextOpacity(base: 0.55, minimum: 4.5, over: ArtworkTint.ink), 0.55, accuracy: 1e-9)
        XCTAssertEqual(Contrast.whiteTextOpacity(base: 0.40, minimum: 3.0, over: ArtworkTint.ink), 0.40, accuracy: 1e-9)
    }

    func testBrightestTintRaisesSecondaryTextToStayLegible() {
        let brightest = ArtworkTint.background(average: white)            // #666666
        let alpha = Contrast.whiteTextOpacity(base: 0.55, minimum: 4.5, over: brightest)
        XCTAssertGreaterThan(alpha, 0.55)
        XCTAssertLessThanOrEqual(alpha, 1)
        let blended = TintColor(r: brightest.r + (1 - brightest.r) * alpha, g: brightest.g + (1 - brightest.g) * alpha,
                                b: brightest.b + (1 - brightest.b) * alpha)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(blended, brightest), 4.5)
    }

    func testPrimaryWhiteTextPassesOnAnyTint() {
        // Worst case: the brightest possible tint. Fully opaque white text must still clear AA.
        let brightest = ArtworkTint.background(average: white)
        XCTAssertGreaterThanOrEqual(Contrast.ratio(white, brightest), 4.5)
    }

    func testRealisticCoversKeepSecondaryTextAtItsBaseOrCloseToIt() {
        // Backgrounds measured from the reference screenshots.
        for bg in [TintColor(r: 72.0 / 255, g: 26.0 / 255, b: 47.0 / 255),
                   TintColor(r: 37.0 / 255, g: 36.0 / 255, b: 28.0 / 255),
                   TintColor(r: 78.0 / 255, g: 61.0 / 255, b: 59.0 / 255)] {
            XCTAssertLessThan(Contrast.whiteTextOpacity(base: 0.55, minimum: 4.5, over: bg), 0.70)
        }
    }
}

final class GrainNoiseTests: XCTestCase {
    func testSizeAndPremultipliedWhite() {
        let px = GrainNoise.pixels(side: 16)
        XCTAssertEqual(px.count, 16 * 16 * 4)
        for i in 0..<(16 * 16) {
            XCTAssertEqual(px[i * 4], px[i * 4 + 3])        // r == a
            XCTAssertEqual(px[i * 4 + 1], px[i * 4 + 3])    // g == a
            XCTAssertEqual(px[i * 4 + 2], px[i * 4 + 3])    // b == a
        }
    }

    func testDeterministicForASeedAndDifferentAcrossSeeds() {
        XCTAssertEqual(GrainNoise.pixels(side: 32), GrainNoise.pixels(side: 32))
        XCTAssertNotEqual(GrainNoise.pixels(side: 32, seed: 1), GrainNoise.pixels(side: 32, seed: 2))
    }

    func testIsSubtleNoiseNotAFlatFill() {
        let px = GrainNoise.pixels(side: 64)
        let alphas = stride(from: 3, to: px.count, by: 4).map { Double(px[$0]) / 255 }
        let mean = alphas.reduce(0, +) / Double(alphas.count)
        XCTAssertGreaterThan(mean, 0.2); XCTAssertLessThan(mean, 0.5)         // skewed toward faint
        XCTAssertGreaterThan(Set(px.indices.filter { $0 % 4 == 3 }.map { px[$0] }).count, 50)   // real variation
    }

    func testEmptyForNonPositiveSide() {
        XCTAssertTrue(GrainNoise.pixels(side: 0).isEmpty)
    }
}
