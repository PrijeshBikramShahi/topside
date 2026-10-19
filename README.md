# Topside: Dynamic Island prototype

**Status (19 October 2026):** debug/release and complete Swift-concurrency builds pass on macOS 26.5.2 with Swift 6.3.3.
All 84 core tests pass. Collapsed/date/battery rendering, Escape dismissal, readable expanded width and accessible date
buttons were verified in the built app; physical display changes, Spotify transport and hardware transitions still require manual testing.

## Build and run
```bash
swift test                                        # TopsideCore unit tests (84)
security find-identity -v -p codesigning          # check available signing identities
bash build_app.sh                                 # Developer ID; Apple Development for local use; otherwise ad-hoc
open build/Topside.app                            # log: ~/Library/Logs/Topside.log
```
Bundle ID `com.prizesh.topside`. Quit/Settings: the capsule icon in the menu bar. Opening the app again while it
runs opens Settings.

## What's in it
- **Slice 1, shell:** accessory app, status item (Hide/Show Island, Settings, Reset Placement, Quit), `DisplayContext` +
  `ActiveDisplayProvider` (menu-bar screen, pointer fallback; re-resolved on screen change, wake, unlock), one
  nonactivating panel sized exactly to the pill, height/offset settings, fullscreen auto-hide heuristic.
- **Slice 2, clock + battery:** minute-aligned clock (wake/timezone/locale resync, 12/24h); event-driven battery
  (IOKit) with discharging, charging, charged, plugged-not-charging, low/critical, Low Power Mode, unknown, no-battery.
- **Slice 3, interaction:** pure reducer (hover dwell 300ms, leave grace 400ms, token-cancelled timers), hover peek
  (date / battery detail), click to pin, outside-click dismissal, and full pinned-panel keyboard navigation with
  Tab/Shift-Tab, arrows, Space, Return and Escape. Hover never takes keyboard focus.
- **Slice 4, dates and activities:** bounded AD→BS conversion through BS 2099; separate
  Copy AD / Copy BS / Copy both actions; charging/power-source transitions; passive default-audio-output changes.
- **Slice 5, Spotify:** lifecycle/permission states, bounded artwork, compact control and pinned transport controls.
- **Slice 6, system integration:** launch-at-login through `SMAppService.mainApp` and an adjustable global show/hide
  shortcut (Off, ⌥Space, ⌃⌥Space, or ⇧⌘Space) implemented with the permission-free Carbon hot-key API.

## Manual test checklist
1. Builds and launches; capsule icon appears; no Dock icon.
2. Pill sits top-center, flush with the screen top. Height/offset sliders move it live.
3. Typing in another app while the pill is hovered/pinned is never interrupted (no focus theft).
4. Hover clock ~0.3s: full AD and romanized BS dates appear. Fast pass across the pill does nothing.
5. Click clock: pinned. Verify Copy AD, Copy BS, Copy both, Escape, outside click and clicking clock again.
6. Battery: unplug/plug charger; percent shown while charging or <=20%; "plugged in, not charging" never says Charging.
7. Sleep/wake, lock/unlock: one panel, same place. Plug/unplug external monitor: pill follows the menu-bar screen.
8. Fullscreen Brave: pill hides within ~1s, returns on exit. Maximized (non-fullscreen) window: pill stays.
9. Hide Island from the menu, Quit, relaunch, run it twice (second launch exits).
10. Rebuild with the same identity and check Spotify prompts later (Phase 2).

## Known limits and deviations from the plan
- Keyboard navigation is available after an explicit pin. VoiceOver labels exist, but a complete VoiceOver audit remains.
- Transparent bottom-corner pixels pass clicks through to the application underneath.
- In fullscreen, dwelling for 500 ms at the top-centre reveals the island; leaving it hides it again after a short grace.
  Ambiguous full-frame windows with both menu bar and Dock hidden require a non-prompting AX fullscreen result or a real
  Space transition, preventing ordinary in-place window zoom from being mistaken for fullscreen.
- The 0A spike source was not available, so panel/fullscreen code was rewritten from the 0A findings, not reused.
- The island suppresses itself while AppKit system/application menus are being tracked, using public window metadata,
  menu-bar input state, and exact callbacks for Topside's own status menu. Escape/Return, selection clicks, and a failsafe
  release suppression without requiring Accessibility permission.
- BS conversion covers 2070–2099. Years through 2084 are cross-checked against official new-year dates; 2085–2099 are
  matching projections from independent open-source tables and are display-only, not suitable for legal use.
- VoiceOver labels exist but are unaudited.


---

# Phase 2: Spotify

## What it does
- **Collapsed:** right side of the pill = album art (22 pt) + compact play/pause. Title and artist never appear at rest.
- **Hover (300 ms):** one line, `Title — Artist` (or `Paused · ...`, or the current problem in plain words).
- **Click the art/pill area:** pins the player: title, artist, Previous / Play-Pause / Next / Open Spotify.
- **Compact button acts without pinning.** It is play/pause, a launcher, "Allow control" or "Open settings" depending on state.
- **States:** not installed, closed (launcher), needs permission, permission denied, idle, paused (last track kept, dimmed art),
  playing, error. Each state shows only controls that can work in it; there are no greyed fake controls.
- **Honest failures:** commands report the real result. A failed command flips the compact icon to a warning and shows
  "Couldn't control Spotify" for 1.8 s. State only changes when a fresh read from Spotify arrives, never optimistically.

## How it talks to Spotify
- **Events:** Spotify's `com.spotify.client.PlaybackStateChanged` distributed notification, plus app launch/quit, trigger a
  coalesced read. A 15 s safety poll runs only while Spotify is running (heals missed events and permission changes).
  The log line `spotify: first playback notification received` tells you whether the event path works on your Spotify version.
- **Reads/commands:** AppleScript through `NSAppleScript` on one serial background queue, 3 s timeout, so a hung Spotify
  can't freeze the island. Passive reads never launch Spotify; the explicit launcher control does.
- **Permission:** the status is checked with `AEDeterminePermissionToAutomateTarget` without prompting. The system dialog appears
  only when you click the "Allow" button on the island. Denied shows a button that opens Privacy > Automation.
- **Artwork:** needs the network (Spotify's `scdn.co` CDN only, https only). Downsampled to the drawn size, 6-entry LRU cache,
  one request in flight, cancelled on track change, previous art cleared immediately on a new track. No disk cache.
- **Privacy:** the log records state changes and error codes only, never track titles or artists.

## Deliberately NOT included (0B evidence not available)
Seek/progress, volume, shuffle/repeat, queue, device picker. Add each only after a spike proves it works on your account.

## Phase 2 test matrix (all Not Tested)
1. Spotify not running: island shows a launcher note; clicking it opens Spotify. Topside never starts it on its own.
2. Spotify running, first time: compact icon is a link glyph; hover says to click; click shows the macOS prompt; Allow, then state appears.
3. Deny (or `tccutil reset AppleEvents com.prizesh.topside`): warning triangle; click opens Automation settings; re-enable, then it recovers within 15 s.
4. Playing: art appears, icon is pause; hover shows `Title — Artist`; pin shows four controls.
5. Pause from Spotify itself: icon flips to play, art dims, within about a second.
6. Skip tracks: old art never shows on the new track; text updates.
7. Next/Previous/Play-Pause from the island work; note that Previous may restart the current track first (Spotify behaviour).
8. Quit Spotify while pinned: player collapses to the launcher state.
9. Free account: note which controls fail; failures should show the warning, never a false success.
10. Rebuild with the same signing identity and check the permission survives (this is the 0B test C that was skipped).
11. Ads: title is an ad label, artist empty, no dangling dash.
12. Check `~/Library/Logs/Topside.log` for `spotify availability=` lines and the first-notification line.

## Known limits
- Property names (`artwork url`, `id`, `player state`) and the notification name are from Spotify's documented scripting
  interface but were not verified against your Spotify version.
- The installed development build uses a stable Apple Development identity for local Automation-consent persistence.
  Distribution outside the Mac App Store still requires a Developer ID Application identity and notarization.
- If you later enable the hardened runtime, add the `com.apple.security.automation.apple-events` entitlement.
- VoiceOver labels exist on the new controls, but the island's controls are mouse-driven (Phase 4 covers keyboard/VO).
- Expanded Spotify panel is 84 pt tall (clock/battery are 66 pt). Pill grew from 184 to 186 pt wide for the art + button.
