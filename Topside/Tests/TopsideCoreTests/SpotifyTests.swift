import XCTest
@testable import TopsideCore

final class SpotifyParserTests: XCTestCase {
    private let sep = SpotifyParser.separator

    func testClosedAndStopped() {
        XCTAssertEqual(SpotifyParser.parse("closed").availability, .closed)
        XCTAssertEqual(SpotifyParser.parse("stopped").availability, .idle)
        XCTAssertNil(SpotifyParser.parse("stopped").track)
    }

    func testPlayingTrack() {
        let s = SpotifyParser.parse(["playing", "spotify:track:abc", "Song", "Artist", "https://i.scdn.co/image/xyz"].joined(separator: sep))
        XCTAssertEqual(s.availability, .playing)
        XCTAssertEqual(s.track?.title, "Song")
        XCTAssertEqual(s.track?.artist, "Artist")
        XCTAssertEqual(s.track?.artworkURL, URL(string: "https://i.scdn.co/image/xyz"))
    }

    func testPausedKeepsTrack() {
        let s = SpotifyParser.parse(["paused", "id", "Song", "Artist", ""].joined(separator: sep))
        XCTAssertEqual(s.availability, .paused)
        XCTAssertEqual(s.track?.title, "Song")
        XCTAssertNil(s.track?.artworkURL)
    }

    func testTitlesWithPunctuationAndUnicodeSurvive() {
        let title = "Pipe | and — dash, 日本語 \"quotes\""
        let s = SpotifyParser.parse(["playing", "id", title, "Ärtist & Co", ""].joined(separator: sep))
        XCTAssertEqual(s.track?.title, title)
        XCTAssertEqual(s.track?.artist, "Ärtist & Co")
    }

    func testNonHTTPSArtworkIsRejected() {
        let s = SpotifyParser.parse(["playing", "id", "Song", "A", "http://example.com/a.jpg"].joined(separator: sep))
        XCTAssertNil(s.track?.artworkURL)
        let junk = SpotifyParser.parse(["playing", "id", "Song", "A", "missing value"].joined(separator: sep))
        XCTAssertNil(junk.track?.artworkURL)
    }

    func testMalformedInputIsAnErrorNotAFakeState() {
        XCTAssertEqual(SpotifyParser.parse("playing").availability, .error)               // track read failed
        XCTAssertEqual(SpotifyParser.parse("").availability, .error)
        XCTAssertEqual(SpotifyParser.parse("something else").availability, .error)
        XCTAssertEqual(SpotifyParser.parse(["playing", "", "", "", ""].joined(separator: sep)).availability, .error)
    }

    func testAdWithNoArtistStillParses() {
        let s = SpotifyParser.parse(["playing", "spotify:ad:1", "Advertisement", "", ""].joined(separator: sep))
        XCTAssertEqual(s.availability, .playing)
        XCTAssertEqual(SpotifyMapper.map(s).detail, "Advertisement")      // no dangling dash
    }
}

final class SpotifyMapperTests: XCTestCase {
    private let track = TrackInfo(id: "1", title: "Song", artist: "Artist", artworkURL: URL(string: "https://i.scdn.co/a"))

    func testPlaying() {
        let d = SpotifyMapper.map(SpotifySnapshot(.playing, track: track))
        XCTAssertEqual(d.detail, "Song — Artist")
        XCTAssertEqual(d.compactIcon, .pause); XCTAssertEqual(d.compactControl, .playPause)
        XCTAssertEqual(d.controls, [.previous, .playPause, .next, .open])
        XCTAssertTrue(d.showsArtwork); XCTAssertFalse(d.isPaused)
        XCTAssertEqual(d.subtitle, "Artist"); XCTAssertEqual(d.artworkURL, track.artworkURL)
    }

    func testPausedIsClearlyPausedAndKeepsTrack() {
        let d = SpotifyMapper.map(SpotifySnapshot(.paused, track: track))
        XCTAssertEqual(d.detail, "Paused · Song — Artist")
        XCTAssertEqual(d.compactIcon, .play); XCTAssertTrue(d.isPaused); XCTAssertEqual(d.subtitle, "Paused · Artist")
    }

    func testIdleIsNeutral() {
        let d = SpotifyMapper.map(SpotifySnapshot(.idle))
        XCTAssertEqual(d.controls, [.playPause, .open])
        XCTAssertFalse(d.detail.contains("—"))
    }

    func testClosedIsALauncher() {
        let d = SpotifyMapper.map(SpotifySnapshot(.closed))
        XCTAssertEqual(d.compactControl, .open); XCTAssertEqual(d.controls, [.open]); XCTAssertFalse(d.showsArtwork)
    }

    func testPermissionStates() {
        let ask = SpotifyMapper.map(SpotifySnapshot(.needsPermission))
        XCTAssertEqual(ask.compactControl, .connect); XCTAssertEqual(ask.controls, [.connect])
        let denied = SpotifyMapper.map(SpotifySnapshot(.permissionDenied))
        XCTAssertEqual(denied.compactControl, .openPrivacySettings); XCTAssertEqual(denied.compactIcon, .warning)
    }

    func testUnavailableStatesOfferNoFakeControls() {
        for a in [SpotifyAvailability.notInstalled, .error] {
            let d = SpotifyMapper.map(SpotifySnapshot(a))
            XCTAssertNil(d.compactControl); XCTAssertTrue(d.controls.isEmpty)
        }
    }

    func testTransportControlsOnlyWhereTheyCanWork() {
        for a in [SpotifyAvailability.closed, .needsPermission, .permissionDenied, .notInstalled, .error] {
            let c = SpotifyMapper.map(SpotifySnapshot(a)).controls
            XCTAssertFalse(c.contains(.next)); XCTAssertFalse(c.contains(.previous)); XCTAssertFalse(c.contains(.playPause))
        }
    }

    func testChangingTrackChangesArtworkURL() {
        let other = TrackInfo(id: "2", title: "B", artist: "C", artworkURL: URL(string: "https://i.scdn.co/b"))
        XCTAssertNotEqual(SpotifyMapper.map(SpotifySnapshot(.playing, track: track)).artworkURL,
                          SpotifyMapper.map(SpotifySnapshot(.playing, track: other)).artworkURL)
    }
}

final class BoundedCacheTests: XCTestCase {
    func testEvictsLeastRecentlyUsed() {
        var c = BoundedCache<String, Int>(capacity: 2)
        c.insert(1, for: "a"); c.insert(2, for: "b")
        _ = c.value(for: "a")                 // a is now most recent
        c.insert(3, for: "c")                 // evicts b
        XCTAssertNil(c.value(for: "b")); XCTAssertEqual(c.value(for: "a"), 1); XCTAssertEqual(c.value(for: "c"), 3)
        XCTAssertEqual(c.count, 2)
    }

    func testNeverExceedsCapacity() {
        var c = BoundedCache<Int, Int>(capacity: 3)
        for i in 0..<100 { c.insert(i, for: i) }
        XCTAssertEqual(c.count, 3)
    }

    func testReinsertingDoesNotGrow() {
        var c = BoundedCache<String, Int>(capacity: 2)
        c.insert(1, for: "a"); c.insert(2, for: "a")
        XCTAssertEqual(c.count, 1); XCTAssertEqual(c.value(for: "a"), 2)
    }
}
