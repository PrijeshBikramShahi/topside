import XCTest
@testable import TopsideCore

final class PlaybackProgressTests: XCTestCase {
    func testLabelFormatting() {
        XCTAssertEqual(PlaybackProgress.label(for: 0), "0:00")
        XCTAssertEqual(PlaybackProgress.label(for: 9), "0:09")
        XCTAssertEqual(PlaybackProgress.label(for: 187), "3:07")
        XCTAssertEqual(PlaybackProgress.label(for: 3723), "1:02:03")
        XCTAssertEqual(PlaybackProgress.label(for: 59.9), "0:59")          // floors, never rounds up early
        XCTAssertEqual(PlaybackProgress.label(for: -5), "0:00")
    }

    func testInitClampsPositionIntoTheTrack() {
        XCTAssertEqual(PlaybackProgress(duration: 100, position: 140).position, 100)
        XCTAssertEqual(PlaybackProgress(duration: 100, position: -3).position, 0)
        XCTAssertEqual(PlaybackProgress(duration: -1, position: 5).duration, 0)
    }

    func testPlayingExtrapolatesFromTheSample() {
        let p = PlaybackProgress(duration: 200, position: 50)
        XCTAssertEqual(p.position(afterSampleBy: 10, isPlaying: true), 60)
        XCTAssertEqual(p.fraction(afterSampleBy: 50, isPlaying: true), 0.5, accuracy: 0.0001)
    }

    func testPausedDoesNotAdvance() {
        let p = PlaybackProgress(duration: 200, position: 50)
        XCTAssertEqual(p.position(afterSampleBy: 30, isPlaying: false), 50)
        XCTAssertEqual(p.fraction(afterSampleBy: 30, isPlaying: false), 0.25, accuracy: 0.0001)
    }

    func testExtrapolationStopsAtTheEndOfTheTrack() {
        let p = PlaybackProgress(duration: 200, position: 190)
        XCTAssertEqual(p.position(afterSampleBy: 60, isPlaying: true), 200)
        XCTAssertEqual(p.fraction(afterSampleBy: 60, isPlaying: true), 1, accuracy: 0.0001)
    }

    func testNegativeElapsedIsIgnoredAndZeroDurationIsSafe() {
        XCTAssertEqual(PlaybackProgress(duration: 200, position: 50).position(afterSampleBy: -10, isPlaying: true), 50)
        XCTAssertEqual(PlaybackProgress(duration: 0, position: 0).fraction(afterSampleBy: 5, isPlaying: true), 0)
    }
}
