import XCTest
import CoreGraphics
@testable import TopsideCore

final class IslandLayoutTests: XCTestCase {
    let m = IslandMetrics()
    let content = IslandContent(clockWidth: 66, batteryWidth: 24)
    let transport: [SpotifyControl] = [.previous, .playPause, .next, .open]

    func testWidthIsContentFit() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(g.size.width, 198)                       // 32 + 66 + 14 + 24 + 14 + 48
        XCTAssertEqual(g.size.height, 36)
    }

    func testDetailStatesUseAvailableReadableWidth() {
        for mode in [IslandMode.peek(.battery), .peek(.spotify), .transient(.audio)] {
            XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: mode).size.width, m.maxWidth)
        }
    }

    func testPinnedStatesUseTheWiderExpandedWidth() {
        XCTAssertGreaterThan(m.expandedWidth, m.maxWidth)
        for mode in [IslandMode.expanded(.clock), .expanded(.battery), .expanded(.spotify)] {
            XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: mode).size.width, m.expandedWidth)
        }
    }

    func testWidthClampsToMinimum() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 50, batteryWidth: 0), mode: .collapsed)
        XCTAssertEqual(g.size.width, 184)                       // natural 136 < 184
    }

    func testWidthClampsToMaximum() {
        let g = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 200, batteryWidth: 62), mode: .collapsed)
        XCTAssertEqual(g.size.width, 284)
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
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .peek(.clock)).size.height, 80)
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .transient(.spotify)).size.height, 66)
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock)).size.height, 124)
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

    func testTransparentBottomCornersAreOutsideVisibleShape() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: 0, y: g.size.height - 0.1),
                                                         size: g.size, cornerRadius: m.cornerRadius))
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: g.size.width - 0.1, y: g.size.height - 0.1),
                                                         size: g.size, cornerRadius: m.cornerRadius))
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: m.cornerRadius, y: g.size.height - 0.1),
                                                        size: g.size, cornerRadius: m.cornerRadius))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 0, y: g.size.height - 0.1), geometry: g, mode: .collapsed), .outside)
    }

    func testCompactButtonAndArtworkHits() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.playRect.midX, y: g.playRect.midY), geometry: g, mode: .collapsed), .compact)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.artworkRect.midX, y: g.artworkRect.midY), geometry: g, mode: .collapsed), .region(.spotify))
    }

    func testDetailAndActionHits() {
        let peek = IslandLayout.geometry(metrics: m, content: content, mode: .peek(.battery))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 45), geometry: peek, mode: .peek(.battery)), .detail(.battery))
        let pinned = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.battery))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: pinned.actionRect.midX, y: pinned.actionRect.midY), geometry: pinned, mode: .expanded(.battery)), .action(.battery))
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 50, y: 40), geometry: pinned, mode: .expanded(.battery)), .detail(.battery))
        XCTAssertEqual(pinned.actionRect.maxY, 36 + 12 + 20)
        XCTAssertLessThan(pinned.actionRect.maxY, pinned.size.height)
    }

    func testDateCopyControlsAreDistinctAndHittable() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock))
        XCTAssertEqual(g.dateControls.map(\.control), [.ad, .bs, .both])
        XCTAssertEqual(g.actionRect, .zero)
        for item in g.dateControls {
            XCTAssertEqual(IslandLayout.hit(CGPoint(x: item.rect.midX, y: item.rect.midY),
                                            geometry: g, mode: .expanded(.clock)), .dateCopy(item.control))
        }
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
        XCTAssertEqual(g.controls[0].rect.width, g.size.width - 32, accuracy: 0.01)
    }

    func testControlsOnlyHitWhenExpanded() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: transport)
        let peek = IslandLayout.geometry(metrics: m, content: c, mode: .peek(.spotify))
        XCTAssertTrue(peek.controls.isEmpty)
    }

    // MARK: Notch-style ears

    private var earMetrics: IslandMetrics { IslandMetrics(earWidth: 8) }

    func testEarsWidenThePillAndInsetContent() {
        let plain = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        let eared = IslandLayout.geometry(metrics: earMetrics, content: content, mode: .collapsed)
        XCTAssertEqual(eared.size.width, plain.size.width + 16)
        XCTAssertEqual(eared.clockRect.minX, plain.clockRect.minX + 8)
        XCTAssertEqual(eared.ear, 8)
        XCTAssertEqual(plain.ear, 0)
        let pill = CGRect(origin: .zero, size: eared.size)
        for r in [eared.clockRect, eared.batteryRect, eared.slotRect, eared.artworkRect, eared.playRect] {
            XCTAssertTrue(pill.contains(r))
        }
    }

    func testEarsKeepTheSameVisibleMarginAsBefore() {
        // Ear + padding on the outside equals the old padding measured from the body edge.
        XCTAssertEqual(earMetrics.contentInset, m.horizontalPadding + 8)
        let g = IslandLayout.geometry(metrics: earMetrics, content: content, mode: .expanded(.clock))
        XCTAssertEqual(g.size.width, earMetrics.expandedWidth + 16)
        XCTAssertEqual(g.size.width - g.dateControls.last!.rect.maxX, earMetrics.contentInset, accuracy: 0.01)
    }

    func testEarRegionIsConcaveAndOutsideBodyIsTransparent() {
        let g = IslandLayout.geometry(metrics: earMetrics, content: content, mode: .collapsed)
        let r = earMetrics.cornerRadius
        // Very top-left corner pixel is carved away by the flare (inside the quarter disc).
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: 1, y: 1), size: g.size, cornerRadius: r, earWidth: 8))
        // Where the flare meets the body edge it is solid.
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: 7.5, y: 1), size: g.size, cornerRadius: r, earWidth: 8))
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: 4, y: 0.5), size: g.size, cornerRadius: r, earWidth: 8))
        // Below the flare, outside the body: pass-through.
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: 3, y: 20), size: g.size, cornerRadius: r, earWidth: 8))
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: g.size.width - 3, y: 20), size: g.size, cornerRadius: r, earWidth: 8))
        // Body.
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: 9, y: 20), size: g.size, cornerRadius: r, earWidth: 8))
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: g.size.width / 2, y: 20), size: g.size, cornerRadius: r, earWidth: 8))
    }

    func testBottomCornersMoveInWithTheBody() {
        let g = IslandLayout.geometry(metrics: earMetrics, content: content, mode: .collapsed)
        let r = earMetrics.cornerRadius
        // Bottom-left of the OUTER box and of the body edge are both clipped by the rounded corner.
        XCTAssertFalse(IslandLayout.containsVisibleShape(CGPoint(x: 8.2, y: g.size.height - 0.1), size: g.size, cornerRadius: r, earWidth: 8))
        XCTAssertTrue(IslandLayout.containsVisibleShape(CGPoint(x: 8 + r, y: g.size.height - 0.1), size: g.size, cornerRadius: r, earWidth: 8))
    }

    func testHitTestingRespectsEars() {
        let g = IslandLayout.geometry(metrics: earMetrics, content: content, mode: .collapsed)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: 3, y: 20), geometry: g, mode: .collapsed, cornerRadius: earMetrics.cornerRadius), .outside)
        XCTAssertEqual(IslandLayout.hit(CGPoint(x: g.clockRect.midX, y: 10), geometry: g, mode: .collapsed,
                                        cornerRadius: earMetrics.cornerRadius), .region(.clock))
    }

    // MARK: Pinned Spotify player

    private func playerContent(progress: Bool) -> IslandContent {
        IslandContent(clockWidth: 66, batteryWidth: 24, spotifyControls: transport,
                      spotifyHasTrack: true, spotifyHasProgress: progress)
    }

    func testPlayerLayoutWithProgress() throws {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        XCTAssertEqual(g.size.height, 36 + m.spotifyPlayerExtra)
        let p = try XCTUnwrap(g.player)
        let pill = CGRect(origin: .zero, size: g.size)
        for r in [p.artworkRect, p.titleRect, p.subtitleRect, p.elapsedRect, p.barRect, p.durationRect] {
            XCTAssertTrue(pill.contains(r), "\(r) escapes \(pill)")
        }
        // Reading order: artwork block, then progress row, then controls, with no overlap.
        let controlsTop = g.controls.filter { $0.control != .open }.map { $0.rect.minY }.min()!
        XCTAssertLessThanOrEqual(p.artworkRect.maxY, p.elapsedRect.minY)
        XCTAssertLessThanOrEqual(p.elapsedRect.maxY, controlsTop)
        XCTAssertLessThanOrEqual(g.controls.map { $0.rect.maxY }.max()!, g.size.height)
        XCTAssertLessThanOrEqual(p.artworkRect.maxX, p.titleRect.minX)
        XCTAssertLessThanOrEqual(p.titleRect.maxY, p.subtitleRect.minY)
        // Bar sits between the two time labels.
        XCTAssertLessThanOrEqual(p.elapsedRect.maxX, p.barRect.minX)
        XCTAssertLessThanOrEqual(p.barRect.maxX, p.durationRect.minX)
        XCTAssertGreaterThan(p.barRect.width, 100)
    }

    func testPlayerLayoutWithoutProgressIsShorterAndHasNoBar() throws {
        let with = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        let without = IslandLayout.geometry(metrics: m, content: playerContent(progress: false), mode: .expanded(.spotify))
        XCTAssertEqual(without.size.height, with.size.height - 20)
        let p = try XCTUnwrap(without.player)
        XCTAssertEqual(p.barRect, .zero)
        XCTAssertEqual(p.elapsedRect, .zero)
        XCTAssertEqual(p.durationRect, .zero)
        XCTAssertLessThanOrEqual(p.artworkRect.maxY, without.controls[0].rect.minY)
    }

    func testPlayerTransportIsCentredIconRowWithOpenAtTopRight() throws {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        func rect(_ c: SpotifyControl) -> CGRect { g.controls.first { $0.control == c }!.rect }
        let prev = rect(.previous), play = rect(.playPause), next = rect(.next), open = rect(.open)
        // Play/pause is the larger, centred circle; previous and next sit symmetrically either side.
        XCTAssertEqual(play.width, 32); XCTAssertEqual(play.height, 32)
        XCTAssertEqual(play.midX, g.size.width / 2, accuracy: 0.01)
        XCTAssertEqual(play.minX - prev.maxX, next.minX - play.maxX, accuracy: 0.01)
        XCTAssertEqual(play.midX - prev.midX, next.midX - play.midX, accuracy: 0.01)
        XCTAssertEqual(prev.minY, play.minY); XCTAssertEqual(next.minY, play.minY)
        // 12 pt bottom margin under the transport row.
        XCTAssertEqual(g.size.height - play.maxY, 12, accuracy: 0.01)
        // The open icon is a 24 pt square in the top-right of the track row, clear of the title.
        XCTAssertEqual(open.width, 24); XCTAssertEqual(open.height, 24)
        XCTAssertEqual(g.size.width - open.maxX, m.contentInset, accuracy: 0.01)
        XCTAssertLessThan(open.minY, g.player!.artworkRect.maxY)
        XCTAssertLessThanOrEqual(g.player!.titleRect.maxX, open.minX)
    }

    func testPlayerLeavesNoTextRectsForTheDetailLines() {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        XCTAssertEqual(g.primaryRect, .zero)
        XCTAssertEqual(g.secondaryRect, .zero)
    }

    // MARK: Date, battery and detail text layout

    func testDateCapsuleIsContiguousEqualThirds() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock))
        let r = g.dateControls.map(\.rect)
        XCTAssertEqual(r.count, 3)
        for (a, b) in zip(r, r.dropFirst()) { XCTAssertEqual(a.maxX, b.minX, accuracy: 0.01) }   // no gaps
        XCTAssertEqual(Set(r.map { $0.width.rounded(.toNearestOrEven) }).count, 1)
        XCTAssertEqual(r[0].minX, m.contentInset)
        XCTAssertEqual(g.size.width - r[2].maxX, m.contentInset, accuracy: 0.01)
        for item in r { XCTAssertEqual(item.height, 26) }
        XCTAssertEqual(g.size.height - r[0].maxY, 12, accuracy: 0.01)
    }

    func testDateTextLinesSitAboveTheCapsule() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.clock))
        let pill = CGRect(origin: .zero, size: g.size)
        XCTAssertTrue(pill.contains(g.primaryRect)); XCTAssertTrue(pill.contains(g.secondaryRect))
        XCTAssertLessThanOrEqual(g.primaryRect.maxY, g.secondaryRect.minY)
        XCTAssertLessThanOrEqual(g.secondaryRect.maxY, g.dateControls[0].rect.minY)
        XCTAssertGreaterThanOrEqual(g.primaryRect.minY, g.bandHeight)
    }

    func testShortDateTitles() {
        XCTAssertEqual(DateCopyControl.allCases.map(\.shortTitle), ["AD", "BS", "Both"])
        XCTAssertEqual(DateCopyControl.both.title, "Copy both")           // accessibility label stays descriptive
    }

    func testBatteryLinkIsRightAlignedAndLevelWithHeadline() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.battery))
        XCTAssertEqual(g.size.width - g.actionRect.maxX, m.contentInset, accuracy: 0.01)
        XCTAssertLessThan(g.actionRect.width, g.size.width / 2)           // a link, not a full-width button
        XCTAssertEqual(g.actionRect.midY, g.primaryRect.midY, accuracy: 1)
        XCTAssertLessThanOrEqual(g.primaryRect.maxX, g.actionRect.minX)   // headline never runs under the link
        XCTAssertLessThanOrEqual(g.primaryRect.maxY, g.secondaryRect.minY)
        XCTAssertLessThanOrEqual(g.secondaryRect.maxY, g.size.height)
    }

    func testPeekUsesTwoCompactTextLines() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .peek(.clock))
        XCTAssertEqual(g.primaryRect.minY, g.bandHeight + 5)
        XCTAssertLessThanOrEqual(g.secondaryRect.maxY, g.size.height)
    }

    func testCollapsedHasNoTextRects() {
        let g = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        XCTAssertEqual(g.primaryRect, .zero); XCTAssertEqual(g.secondaryRect, .zero)
    }

    func testSideMarginIsSixteen() {
        XCTAssertEqual(m.horizontalPadding, 16)
        XCTAssertEqual(m.contentInset, 16)
        XCTAssertEqual(IslandMetrics(earWidth: 8).contentInset, 24)
    }

    func testPlayerOnlyInPinnedSpotifyWithATrack() {
        let c = playerContent(progress: true)
        XCTAssertNil(IslandLayout.geometry(metrics: m, content: c, mode: .peek(.spotify)).player)
        XCTAssertNil(IslandLayout.geometry(metrics: m, content: c, mode: .expanded(.clock)).player)
        XCTAssertNil(IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.spotify)).player)   // no track
        XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: .expanded(.spotify)).size.height, 120)
    }

    func testPlayerControlsStillHittable() {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        for item in g.controls {
            XCTAssertEqual(IslandLayout.hit(CGPoint(x: item.rect.midX, y: item.rect.midY), geometry: g, mode: .expanded(.spotify)),
                           .control(item.control))
        }
    }

    func testCompactPlayButtonIsNotClickableWhilePlayerIsShown() {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        let hit = IslandLayout.hit(CGPoint(x: g.playRect.midX, y: g.playRect.midY), geometry: g, mode: .expanded(.spotify))
        XCTAssertNotEqual(hit, .compact)
        XCTAssertEqual(hit, .region(.spotify))
    }

    // MARK: Wi-Fi icon and output chip

    func testWifiSitsBeforeTheBatteryAndWidensTheIsland() {
        let without = IslandLayout.geometry(metrics: m, content: content, mode: .collapsed)
        let with = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 66, batteryWidth: 24, wifiWidth: 16), mode: .collapsed)
        XCTAssertEqual(with.size.width, without.size.width + 16 + IslandLayout.wifiIconGap)
        XCTAssertEqual(with.wifiRect.width, 16)
        XCTAssertEqual(with.wifiRect.minX, with.batteryRect.minX)            // leading part of the shared hover region
        XCTAssertEqual(with.batteryRect.width, 24 + IslandLayout.wifiIconGap + 16)
        XCTAssertLessThanOrEqual(with.batteryRect.maxX, with.slotRect.minX)
        XCTAssertEqual(without.wifiRect, .zero)
    }

    func testWifiIsDroppedWhenItWouldNotFitAndWithoutABattery() {
        let wide = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 120, batteryWidth: 62, wifiWidth: 16), mode: .collapsed)
        XCTAssertEqual(wide.wifiRect, .zero)
        XCTAssertEqual(wide.batteryRect.width, 62)
        let none = IslandLayout.geometry(metrics: m, content: IslandContent(clockWidth: 66, batteryWidth: 0, wifiWidth: 16), mode: .collapsed)
        XCTAssertEqual(none.wifiRect, .zero)
    }

    func testWifiDecisionDoesNotChangeBetweenModes() {
        let c = IslandContent(clockWidth: 66, batteryWidth: 24, wifiWidth: 16)
        for mode in [IslandMode.collapsed, .peek(.clock), .expanded(.battery)] {
            XCTAssertEqual(IslandLayout.geometry(metrics: m, content: c, mode: mode).wifiRect.width, 16)
        }
    }

    func testOutputChipLivesInThePinnedPlayerLeftOfTheTransport() throws {
        let g = IslandLayout.geometry(metrics: m, content: playerContent(progress: true), mode: .expanded(.spotify))
        XCTAssertNotEqual(g.outputRect, .zero)
        XCTAssertTrue(CGRect(origin: .zero, size: g.size).contains(g.outputRect))
        let previous = try XCTUnwrap(g.controls.first { $0.control == .previous })
        XCTAssertLessThanOrEqual(g.outputRect.maxX, previous.rect.minX)
        XCTAssertEqual(g.outputRect.minY, previous.rect.minY)
        let centre = CGPoint(x: g.outputRect.midX, y: g.outputRect.midY)
        XCTAssertEqual(IslandLayout.hit(centre, geometry: g, mode: .expanded(.spotify)), .audioOutput)
    }

    func testNoOutputChipOutsideThePlayer() {
        for mode in [IslandMode.collapsed, .peek(.spotify), .expanded(.clock), .expanded(.battery)] {
            XCTAssertEqual(IslandLayout.geometry(metrics: m, content: content, mode: mode).outputRect, .zero)
        }
    }
}
