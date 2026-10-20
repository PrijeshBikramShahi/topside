import CoreWLAN
import Foundation
import TopsideCore

/// CoreWLAN delegate callbacks arrive on arbitrary threads; this bridge only forwards "something changed".
private final class WiFiEventBridge: NSObject, CWEventDelegate {
    let onEvent: () -> Void
    init(onEvent: @escaping () -> Void) { self.onEvent = onEvent }
    func powerStateDidChange(forWiFiInterfaceWithName interfaceName: String) { onEvent() }
    func ssidDidChange(forWiFiInterfaceWithName interfaceName: String) { onEvent() }
    func linkDidChange(forWiFiInterfaceWithName interfaceName: String) { onEvent() }
    func linkQualityDidChange(forWiFiInterfaceWithName interfaceName: String, rssi: Int, transmitRate: Double) { onEvent() }
}

/// Event-driven Wi-Fi state (no polling). It reads only power, association and signal strength.
/// The network name is never read, so no Location permission is needed.
@MainActor
final class WiFiService {
    var onChange: ((WiFiSnapshot) -> Void)?
    private let client = CWWiFiClient.shared()
    private var bridge: WiFiEventBridge?

    func start() {
        guard bridge == nil else { return }
        let bridge = WiFiEventBridge { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        self.bridge = bridge                   // the client holds its delegate weakly
        client.delegate = bridge
        for event in [CWEventType.powerDidChange, .linkDidChange, .linkQualityDidChange, .ssidDidChange] {
            do { try client.startMonitoringEvent(with: event) }
            catch { Log.info("wifi monitoring failed event=\(event.rawValue) error=\(error.localizedDescription)") }
        }
        refresh()
    }

    func refresh() { onChange?(readSnapshot()) }

    private func readSnapshot() -> WiFiSnapshot {
        guard let interface = client.interface() else { return WiFiSnapshot(hasInterface: false, powerOn: nil, rssi: nil) }
        return WiFiSnapshot(hasInterface: true, powerOn: interface.powerOn(), rssi: interface.rssiValue())
    }
}
