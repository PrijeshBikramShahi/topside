import XCTest
@testable import TopsideCore

final class FullscreenDecisionTests: XCTestCase {
    func testNonMatchingBoundsAreNeverFullscreen() {
        XCTAssertFalse(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: false,
            systemChromeIsAmbiguous: false,
            accessibilityFullscreen: true,
            secondsSinceSpaceChange: 0
        ))
    }

    func testBoundsAreEnoughWhenSystemChromeLeavesVisibleGeometry() {
        XCTAssertTrue(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: false,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: .infinity
        ))
    }

    func testAccessibilityResultWinsForAmbiguousAutoHiddenChrome() {
        XCTAssertTrue(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: true,
            secondsSinceSpaceChange: .infinity
        ))
        XCTAssertFalse(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: false,
            secondsSinceSpaceChange: 0
        ))
    }

    func testRecentSpaceTransitionIsFallbackWithoutAccessibility() {
        XCTAssertTrue(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: 1.49
        ))
        XCTAssertFalse(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: 1.5
        ))
    }

    func testClockSkewCannotCreateFullscreenEvidence() {
        XCTAssertFalse(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: -0.1
        ))
    }

    func testConfirmedFullscreenPersistsAfterTransitionWindowExpires() {
        XCTAssertTrue(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: 30,
            preserveConfirmedFullscreen: true
        ))
    }

    func testNewSpaceGenerationInvalidatesSameAppConfirmation() {
        XCTAssertFalse(FullscreenDecision.isFullscreen(
            boundsMatchDisplay: true,
            systemChromeIsAmbiguous: true,
            accessibilityFullscreen: nil,
            secondsSinceSpaceChange: 0.5,
            preserveConfirmedFullscreen: false,
            spaceTransitionCanConfirm: false
        ))
    }
}
