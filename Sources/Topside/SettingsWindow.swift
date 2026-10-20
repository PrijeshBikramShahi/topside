import AppKit
import SwiftUI
import TopsideCore

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Island") {
                HStack {
                    Text("Height")
                    Slider(value: $prefs.height, in: 30...44, step: 1)
                    Text("\(Int(prefs.height)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                HStack {
                    Text("Vertical offset")
                    Slider(value: $prefs.topOffset, in: 0...12, step: 1)
                    Text("\(Int(prefs.topOffset)) pt").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Toggle("Notch-style top corners", isOn: $prefs.notchCorners)
                Text("Curves the top corners outward so the island blends into the screen edge. Applies when the vertical offset is 0.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let ctx = ActiveDisplayProvider().currentContext() {
                    Text("Menu bar on this display: \(ctx.menuBarHeight == 0 ? "hidden (auto-hide)" : "\(Int(ctx.menuBarHeight)) pt")")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Clock") {
                Picker("Format", selection: $prefs.clockStyle) {
                    Text("Follow system").tag(ClockStyle.system)
                    Text("12-hour").tag(ClockStyle.twelveHour)
                    Text("24-hour").tag(ClockStyle.twentyFourHour)
                }
            }
            Section("Appearance") {
                Toggle("Tint with album artwork", isOn: $prefs.albumTint)
                HStack {
                    Text("Tint strength")
                    Slider(value: $prefs.tintStrength, in: 0.25...1)
                    Text("\(Int(prefs.tintStrength * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                .disabled(!prefs.albumTint)
                Text("The pinned player takes the album's colour. Other states get a faint hint of it. The collapsed island stays black.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Film grain", isOn: $prefs.grain)
                HStack {
                    Text("Grain strength")
                    Slider(value: $prefs.grainStrength, in: 0.1...1)
                    Text("\(Int(prefs.grainStrength * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                .disabled(!prefs.grain)
                Text("Grain is off while the island is collapsed, and when macOS Reduce Transparency is on.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Fullscreen") {
                Toggle("Hide island when the frontmost app is fullscreen", isOn: $prefs.hideInFullscreen)
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.setLaunchAtLogin($0) }
                ))
                if let error = prefs.launchAtLoginError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Picker("Show or hide island", selection: $prefs.globalShortcut) {
                    ForEach(GlobalShortcut.allCases) { shortcut in
                        Text(shortcut.title).tag(shortcut)
                    }
                }
            }
            Section {
                Button("Reset to Defaults") { prefs.resetToDefaults() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Topside Settings"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(prefs: .shared))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
