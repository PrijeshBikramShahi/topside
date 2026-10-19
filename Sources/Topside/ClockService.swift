import AppKit
import TopsideCore

/// Minute-aligned ticks; resyncs on wake, clock/timezone/locale change, and day change.
@MainActor
final class ClockService: NSObject {
    var onTick: (() -> Void)?
    private var timer: Timer?

    func start() {
        let nc = NotificationCenter.default
        let names: [Notification.Name] = [.NSSystemClockDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange,
                                          NSLocale.currentLocaleDidChangeNotification]
        for n in names { nc.addObserver(self, selector: #selector(resync), name: n, object: nil) }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resync),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        resync()
    }

    @objc private func resync() {
        onTick?()
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        // +50ms so we are safely past the boundary and never show the previous minute.
        let fire = ClockFormat.nextMinuteBoundary(after: Date()).addingTimeInterval(0.05)
        let t = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resync() }
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
