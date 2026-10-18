import XCTest
@testable import TopsideCore

final class InteractionReducerTests: XCTestCase {
    private func reduce(_ s: inout InteractionState, _ e: InteractionEvent) -> [InteractionEffect] {
        InteractionReducer.reduce(&s, e)
    }

    func testDwellThenPeek() {
        var s = InteractionState()
        let fx = reduce(&s, .pointerMoved(.clock))
        XCTAssertEqual(fx, [.startDwell(token: s.token, delay: Timing.hoverDwell)])
        XCTAssertEqual(s.mode, .collapsed)          // not yet
        _ = reduce(&s, .dwellElapsed(token: s.token))
        XCTAssertEqual(s.mode, .peek(.clock))
    }

    func testFastPassNeverExpands() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock))
        let staleToken = s.token
        _ = reduce(&s, .pointerMoved(nil))          // left before the dwell finished
        _ = reduce(&s, .dwellElapsed(token: staleToken))
        XCTAssertEqual(s.mode, .collapsed)
    }

    func testMovingWithinSameRegionDoesNotRestartDwell() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock))
        let t = s.token
        XCTAssertEqual(reduce(&s, .pointerMoved(.clock)), [])
        XCTAssertEqual(s.token, t)
    }

    func testLeaveStartsGraceAndCollapses() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.battery)); _ = reduce(&s, .dwellElapsed(token: s.token))
        let fx = reduce(&s, .pointerMoved(nil))
        XCTAssertEqual(fx, [.startGrace(token: s.token, delay: Timing.leaveGrace)])
        XCTAssertEqual(s.mode, .peek(.battery))     // still showing during grace
        _ = reduce(&s, .graceElapsed(token: s.token))
        XCTAssertEqual(s.mode, .collapsed)
    }

    func testReenteringCancelsGrace() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock)); _ = reduce(&s, .dwellElapsed(token: s.token))
        _ = reduce(&s, .pointerMoved(nil))
        let graceToken = s.token
        _ = reduce(&s, .pointerMoved(.clock))
        _ = reduce(&s, .graceElapsed(token: graceToken))   // stale
        XCTAssertEqual(s.mode, .peek(.clock))
    }

    func testPeekSwitchesBetweenRegionsImmediately() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock)); _ = reduce(&s, .dwellElapsed(token: s.token))
        _ = reduce(&s, .pointerMoved(.battery))
        XCTAssertEqual(s.mode, .peek(.battery))
    }

    func testClickPinsAndSecondClickUnpins() {
        var s = InteractionState()
        _ = reduce(&s, .clicked(.clock))
        XCTAssertEqual(s.mode, .expanded(.clock))
        _ = reduce(&s, .clicked(.clock))
        XCTAssertEqual(s.mode, .collapsed)
    }

    func testAtMostOnePinnedPanel() {
        var s = InteractionState()
        _ = reduce(&s, .clicked(.clock)); _ = reduce(&s, .clicked(.battery))
        XCTAssertEqual(s.mode, .expanded(.battery))
    }

    func testPinnedIgnoresPointerExit() {
        var s = InteractionState()
        _ = reduce(&s, .clicked(.clock))
        _ = reduce(&s, .pointerMoved(nil))
        _ = reduce(&s, .graceElapsed(token: s.token))
        XCTAssertEqual(s.mode, .expanded(.clock))
    }

    func testOutsideClickAndEscapeCollapse() {
        var s = InteractionState()
        _ = reduce(&s, .clicked(.clock)); _ = reduce(&s, .outsideClick)
        XCTAssertEqual(s.mode, .collapsed)
        _ = reduce(&s, .clicked(.battery)); _ = reduce(&s, .escape)
        XCTAssertEqual(s.mode, .collapsed)
    }

    func testEscapeBeatsPendingTimers() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock))
        let dwell = s.token
        _ = reduce(&s, .escape)
        _ = reduce(&s, .dwellElapsed(token: dwell))
        XCTAssertEqual(s.mode, .collapsed)
    }

    func testSuppressionCollapsesAndBlocksPreviews() {
        var s = InteractionState()
        _ = reduce(&s, .clicked(.clock))
        _ = reduce(&s, .setSuppressed(true))
        XCTAssertEqual(s.mode, .collapsed)
        XCTAssertEqual(reduce(&s, .pointerMoved(.clock)), [.cancelTimers])
        _ = reduce(&s, .dwellElapsed(token: s.token))
        XCTAssertEqual(s.mode, .collapsed)
        _ = reduce(&s, .clicked(.clock))
        XCTAssertEqual(s.mode, .collapsed)
        _ = reduce(&s, .setSuppressed(false))
        _ = reduce(&s, .pointerMoved(nil)); _ = reduce(&s, .pointerMoved(.clock))
        _ = reduce(&s, .dwellElapsed(token: s.token))
        XCTAssertEqual(s.mode, .peek(.clock))
    }

    func testNeverCollapsesDuringDrag() {
        var s = InteractionState()
        _ = reduce(&s, .pointerMoved(.clock)); _ = reduce(&s, .dwellElapsed(token: s.token))
        _ = reduce(&s, .dragBegan)
        _ = reduce(&s, .pointerMoved(nil))
        _ = reduce(&s, .graceElapsed(token: s.token))
        XCTAssertEqual(s.mode, .peek(.clock))
        let fx = reduce(&s, .dragEnded)             // grace restarts once the drag ends
        XCTAssertEqual(fx, [.startGrace(token: s.token, delay: Timing.leaveGrace)])
        _ = reduce(&s, .graceElapsed(token: s.token))
        XCTAssertEqual(s.mode, .collapsed)
    }
}
