import AppKit
import ApplicationServices
import TopsideCore

/// Everything that talks to Spotify via Apple Events. Not main-actor: always called from SpotifyService's serial queue,
/// so a slow or hung Spotify can never block the UI. Never launches Spotify (every script checks "is running" first).
enum SpotifyBridge {
    static let bundleID = "com.spotify.client"
    private static let wildcard: OSType = 0x2A2A2A2A   // '****'

    struct ScriptFailure: Error { let code: Int; let message: String }

    enum Permission { case granted, notDetermined, denied, targetNotRunning, unknown(Int32) }

    static var installedURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// prompt == false: pure status check, never shows the system dialog. prompt == true: shows it if undecided
    /// (blocks until the user answers; only call off the main thread).
    static func permission(prompt: Bool) -> Permission {
        guard let desc = NSAppleEventDescriptor(bundleIdentifier: bundleID).aeDesc else { return .unknown(-1) }
        let status = AEDeterminePermissionToAutomateTarget(desc, wildcard, wildcard, prompt)
        switch status {
        case 0: return .granted
        case -1744: return .notDetermined      // errAEEventWouldRequireUserConsent
        case -1743: return .denied             // errAEEventNotPermitted
        case -600: return .targetNotRunning    // procNotFound
        default: return .unknown(status)
        }
    }

    // MARK: Reading

    // Variable names are deliberately long and unusual: short names such as `st` collide with terms in
    // Spotify's scripting dictionary inside the tell block and fail to compile (error -2741).
    private static let readScript = """
    if application "Spotify" is not running then return "closed"
    set theSeparator to ASCII character 31
    with timeout of 3 seconds
        tell application "Spotify"
            set theStateText to (player state as text)
            try
                set theCurrentTrack to current track
                set theTrackId to (id of theCurrentTrack) as text
                set theTrackName to (name of theCurrentTrack) as text
                set theTrackArtist to (artist of theCurrentTrack) as text
                set theArtworkUrl to ""
                try
                    set theArtworkUrl to (artwork url of theCurrentTrack) as text
                end try
                set theDurationMillis to ""
                set thePositionSeconds to ""
                try
                    set theDurationMillis to ((duration of theCurrentTrack) as integer) as text
                    set thePositionSeconds to ((player position) as integer) as text
                end try
                return theStateText & theSeparator & theTrackId & theSeparator & theTrackName & theSeparator & theTrackArtist & theSeparator & theArtworkUrl & theSeparator & theDurationMillis & theSeparator & thePositionSeconds
            on error
                return theStateText
            end try
        end tell
    end timeout
    """

    static func readSnapshot() -> SpotifySnapshot {
        guard installedURL != nil else { return SpotifySnapshot(.notInstalled) }
        guard isRunning else { return SpotifySnapshot(.closed) }
        switch permission(prompt: false) {
        case .granted, .unknown: break                       // unknown: let the script itself report
        case .notDetermined: return SpotifySnapshot(.needsPermission)
        case .denied: return SpotifySnapshot(.permissionDenied)
        case .targetNotRunning: return SpotifySnapshot(.closed)
        }
        switch run(readScript) {
        case .success(let text): return SpotifyParser.parse(text)
        case .failure(let f):
            Log.info("spotify read failed code=\(f.code) message=\(String(f.message.prefix(160)))")
            switch f.code {
            case -1743: return SpotifySnapshot(.permissionDenied)
            case -1744: return SpotifySnapshot(.needsPermission)
            case -600, -609: return SpotifySnapshot(.closed)
            default: return SpotifySnapshot(.error)
            }
        }
    }

    // MARK: Commands

    /// Returns true only if Spotify accepted the command (or, for .connect, permission is now granted).
    static func perform(_ control: SpotifyControl) -> Bool {
        let verb: String
        switch control {
        case .connect:
            if case .granted = permission(prompt: true) { return true }
            return false
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .open, .openPrivacySettings: return false      // handled on the main thread by the caller
        }
        let source = """
        if application "Spotify" is not running then error number -600
        with timeout of 3 seconds
            tell application "Spotify" to \(verb)
        end timeout
        """
        switch run(source) {
        case .success: return true
        case .failure(let f):
            Log.info("spotify command \(verb) failed code=\(f.code) message=\(String(f.message.prefix(160)))")
            return false
        }
    }

    // MARK: Execution

    private static func run(_ source: String) -> Result<String, ScriptFailure> {
        guard let script = NSAppleScript(source: source) else { return .failure(ScriptFailure(code: -1, message: "compile")) }
        var info: NSDictionary?
        let result = script.executeAndReturnError(&info)
        if let info {
            let code = (info["NSAppleScriptErrorNumber"] as? Int) ?? -1
            let message = (info["NSAppleScriptErrorMessage"] as? String) ?? ""
            return .failure(ScriptFailure(code: code, message: message))
        }
        return .success(result.stringValue ?? "")
    }
}
