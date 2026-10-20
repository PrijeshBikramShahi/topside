import XCTest
@testable import TopsideCore

final class IslandMotionTests: XCTestCase {
    func testEndpointsAreExact() {
        for growing in [true, false] {
            XCTAssertEqual(IslandMotion.eased(0, growing: growing), 0, accuracy: 1e-12)
            XCTAssertEqual(IslandMotion.eased(1, growing: growing), 1, accuracy: 1e-12)
        }
    }

    func testInputIsClamped() {
        XCTAssertEqual(IslandMotion.eased(-1, growing: true), 0, accuracy: 1e-12)
        XCTAssertEqual(IslandMotion.eased(2, growing: false), 1, accuracy: 1e-12)
    }

    func testGrowingOvershootsSlightlyThenSettles() {
        let samples = (0...100).map { IslandMotion.eased(Double($0) / 100, growing: true) }
        let peak = samples.max()!
        XCTAssertGreaterThan(peak, 1.02)      // visible spring
        XCTAssertLessThan(peak, 1.08)         // but restrained
        XCTAssertEqual(samples.last!, 1, accuracy: 1e-12)
    }

    func testShrinkingNeverOvershootsAndIsMonotonic() {
        let samples = (0...100).map { IslandMotion.eased(Double($0) / 100, growing: false) }
        XCTAssertLessThanOrEqual(samples.max()!, 1 + 1e-12)
        for (a, b) in zip(samples, samples.dropFirst()) { XCTAssertLessThanOrEqual(a, b + 1e-12) }
    }

    func testClosingIsFasterThanOpening() {
        XCTAssertLessThan(IslandMotion.duration(growing: false), IslandMotion.duration(growing: true))
    }
}
