import XCTest
@testable import TopsideCore

final class SpotifyProgressParsingTests: XCTestCase {
    private let sep = SpotifyParser.separator

    private func line(_ fields: [String]) -> String { fields.joined(separator: sep) }

    func testParsesDurationAndPosition() {
        let s = SpotifyParser.parse(line(["playing", "id", "Song", "Artist", "https://i.scdn.co/x", "187000", "42"]))
        XCTAssertEqual(s.availability, .playing)
        XCTAssertEqual(s.progress, PlaybackProgress(duration: 187, position: 42))
        XCTAssertEqual(s.track?.title, "Song")
    }

    func testOlderFiveFieldFormatHasNoProgress() {
        let s = SpotifyParser.parse(line(["paused", "id", "Song", "Artist", ""]))
        XCTAssertEqual(s.availability, .paused)
        XCTAssertNil(s.progress)
    }

    func testUnusableProgressIsIgnoredWithoutBreakingTheTrack() {
        for bad in [["", ""], ["0", "5"], ["abc", "5"], ["1000", "-4"], ["1000", "x"]] {
            let s = SpotifyParser.parse(line(["playing", "id", "Song", "Artist", "", bad[0], bad[1]]))
            XCTAssertEqual(s.availability, .playing, "\(bad)")
            XCTAssertEqual(s.track?.title, "Song")
            XCTAssertNil(s.progress, "\(bad)")
        }
    }

    func testPositionPastTheEndIsClamped() {
        let s = SpotifyParser.parse(line(["playing", "id", "Song", "Artist", "", "10000", "99"]))
        XCTAssertEqual(s.progress?.position, 10)
    }

    func testWhitespaceAroundNumbersIsTolerated() {
        let s = SpotifyParser.parse(line(["playing", "id", "Song", "Artist", "", " 60000 ", " 7\n"]))
        XCTAssertEqual(s.progress, PlaybackProgress(duration: 60, position: 7))
    }

    func testStatesWithoutATrackNeverCarryProgress() {
        XCTAssertNil(SpotifyParser.parse("closed").progress)
        XCTAssertNil(SpotifyParser.parse("stopped").progress)
        XCTAssertNil(SpotifyParser.parse("playing").progress)
    }
}
