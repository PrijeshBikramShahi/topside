import XCTest
import CoreGraphics
@testable import TopsideCore

final class IslandLayoutTests: XCTestCase {
    let m = IslandMetrics()
    let content = IslandContent(clockWidth: 66, batteryWidth: 24)
    let transport: [SpotifyControl] = [.previous, .playPause, .next, .open]

    func testWidthIsContentFit() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(g.size.width, 186)                       // 28 + 66 + 10 + 24 + 10 + 48
        XCTAssertEqual(g.size.height, 36)
    }

    func testWidthClampsToMinimum() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 50, batteryWidth: 0), mode: .collapsed)
        XCTAssertEqual(g.size.width, 184)                       // natural 136 < 184
    }

    func testWidthClampsToMaximum() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 200, batteryWidth: 62), mode: .collapsed)
        XCTAssertEqual(g.size.width, 240)
    }

    func testBatteryHiddenWhenWidthZero() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 66, batteryWidth: 0), mode: .collapsed)
        XCTAssertEqual(g.batteryRect, .zero)
    }

    func testRectsStayInsidePill() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        let pill = CGRect(origin: .zero, size: g.size)
        for r in [g.clockRect, g.batteryRect, g.slotRect, g.artworkRect, g.playRect] { XCTAssertTrue(pill.contains(r)) }
        XCTAssertLessThanOrEqual(g.batteryRect.maxX, g.slotRect.minX)
        XCTAssertLessThanOrEqual(g.artworkRect.maxX, g.playRect.minX)       // artwork and button never overlap
        XCTAssertTrue(g.slotRect.contains(g.artworkRect)); XCTAssertTrue(g.slotRect.contains(g.playRect))
    }

    func testHeightGrowsWithMode() {
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .peek(.clock)).size.height, 66)
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock)).size.height, 102)
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.spotify)).size.height, 120)
    }

    func testPanelIsCenteredAndTopAttached() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        for display in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: -200, width: 2560, height: 1440)] {
            let f = IslandLayout.panelFrame(geometry: g, displayFrame: display, topOffset: 0, scale: 2)
            XCTAssertEqual(f.midX, display.midX, accuracy: 0.5)
            XCTAssertEqual(f.maxY, display.maxY, accuracy: 0.01)
        }
    }

    func testTopOffsetMovesPanelDown() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        let f = IslandLayout.panelFrame(geometry: g, displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), topOffset: 6, scale: 2)
        XCTAssertEqual(f.maxY, 894, accuracy: 0.01)
    }

    func testPanelFrameSnapsToPixels() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 67, batteryWidth: 24), mode: .collapsed)
        let f = IslandLayout.panelFrame(geometry: g, displayFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), topOffset: 0, scale: 2)
        XCTAssertEqual((f.minX * 2).truncatingRemainder(dividingBy: 1), 0, accuracy: 0.0001)
    }

    func testHitTesting() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 2, y: 10), geometry: g, mode: .collapsed), .region(.clock))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.batteryRect.midX, y: 10), geometry: g, mode: .collapsed), .region(.battery))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.size.width - 2, y: 10), geometry: g, mode: .collapsed), .region(.spotify))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: -1, y: 10), geometry: g, mode: .collapsed), .outside)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 50), geometry: g, mode: .collapsed), .outside)
    }

    func testCompactButtonAndArtworkHits() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.playRect.midX, y: g.playRect.midY), geometry: g, mode: .collapsed), .compact)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.artworkRect.midX, y: g.artworkRect.midY), geometry: g, mode: .collapsed), .region(.spotify))
    }

    func testDetailAndActionHits() {
        let peek = IslandLayout.geometry(metrics: m, content: content, mode: .peek(.battery))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 45), geometry: peek, mode: .peek(.battery)), .detail(.battery))
        let pinned = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: pinned.actionRect.midX, y: pinned.actionRect.midY), geometry: pinned, mode: .expanded(.clock)), .action(.clock))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 40), geometry: pinned, mode: .expanded(.clock)), .detail(.clock))
        XCTAssertEqual(pinned.actionRect.maxY, 36 + 30 + 24)
        XCTAssertLessThan(pinned.actionRect.maxY, pinned.size.height)
    }

    func testNoActionRectWhenOnlyPeeking() {
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .peek(.clock)).actionRect, .zero)
    }

    func testSpotifyControlsAreLaidOutInsideThePill() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: transport)
        let g = IslandLayout.geometry(metrics: m, content: c, mode: .expanded(.spotify))
        XCTAssertEqual(g.controls.map(\.control), transport)
        XCTAssertEqual(g.actionRect, .zero)                       // clock/battery action button is not used here
        let pill = CGRect(origin: .zero, size: g.size)
        for item in g.controls { XCTAssertTrue(pill.contains(item.rect)) }
        for (a, b) in zip(g.controls, g.controls.dropFirst()) { XCTAssertLessThanOrEqual(a.rect.maxX, b.rect.minX) }
    }

    func testSpotifyControlHits() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: transport)
        let g = IslandLayout.geometry(metrics: m, content: c, mode: .expanded(.spotify))
        for item in g.controls {
            XCTAssertEqual(IslandLayout.hit(CGPoint(x: item.rect.midX, y: item.rect.midY), geometry: g, mode: .expanded(.spotify)),
                           .control(item.control))
        }
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 45), geometry: g, mode: .expanded(.spotify)), .detail(.spotify))
    }

    func testSingleControlFillsRow() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: [.open])
        let g = IslandLayout.geometry(metrics: m, content: c, mode: .expanded(.spotify))
        XCTAssertEqual(g.controls.count, 1)
        XCTAssertEqual(g.controls[0].rect.width, g.size.width - 28, accuracy: 0.01)
    }

    func testControlsOnlyHitWhenExpanded() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: transport)
        let peek = IslandLayout.geometry(metrics: m, content: c, mode: .peek(.spotify))
        XCTAssertTrue(peek.controls.isEmpty)
    }
}
