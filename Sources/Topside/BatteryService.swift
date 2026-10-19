import AppKit
import IOKit.ps
import TopsideCore

/// Event-driven (IOKit power-source notifications); no polling.
@MainActor
final class BatteryService: NSObject {
    var onChange: ((PowerSnapshot) -> Void)?
    private var source: CFRunLoopSource?
    private var lastSnapshot: PowerSnapshot?
    private var settleTask: Task<Void, Never>?

    func start() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { ctx in
            guard let ctx else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in service.refresh() }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            source = src
        }
        NotificationCenter.default.addObserver(self, selector: #selector(lowPowerChanged),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
        refresh()
    }

    @objc private func lowPowerChanged() { refresh() }

    func refresh() {
        let snapshot = readSnapshot()
        let wasResolved = lastSnapshot.map(isResolved) ?? false
        guard !wasResolved || isResolved(snapshot) else {
            // Power-source notifications can momentarily expose an empty or
            // incomplete list while AC is disconnected. Keep the last real
            // battery state until IOKit settles instead of collapsing layout.
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard let self, !Task.isCancelled else { return }
                self.publish(self.readSnapshot())
            }
            return
        }
        publish(snapshot)
    }

    private func publish(_ snapshot: PowerSnapshot) {
        settleTask?.cancel()
        settleTask = nil
        lastSnapshot = snapshot
        onChange?(snapshot)
    }

    private func isResolved(_ snapshot: PowerSnapshot) -> Bool {
        !snapshot.hasBattery || (snapshot.percent != nil && snapshot.isOnACPower != nil)
    }

    private func readSnapshot() -> PowerSnapshot {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerSnapshot(hasBattery: true, percent: nil, isOnACPower: nil, isCharging: nil, isCharged: nil, lowPowerMode: lowPower)
        }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (desc[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            var percent: Int?
            if let cur = desc[kIOPSCurrentCapacityKey] as? Int, let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                percent = Int((Double(cur) / Double(max) * 100).rounded())
            }
            let onAC = (desc[kIOPSPowerSourceStateKey] as? String).map { $0 == kIOPSACPowerValue }
            return PowerSnapshot(hasBattery: true, percent: percent, isOnACPower: onAC,
                                 isCharging: desc[kIOPSIsChargingKey] as? Bool,
                                 isCharged: desc[kIOPSIsChargedKey] as? Bool, lowPowerMode: lowPower)
        }
        return PowerSnapshot(hasBattery: false, percent: nil, isOnACPower: nil, isCharging: nil, isCharged: nil, lowPowerMode: lowPower)
    }
}
