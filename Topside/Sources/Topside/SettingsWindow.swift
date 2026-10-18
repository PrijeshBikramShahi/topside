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
            Section("Fullscreen") {
                Toggle("Hide island when the frontmost app is fullscreen", isOn: $prefs.hideInFullscreen)
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
