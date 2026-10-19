import CoreAudio
import Foundation

struct AudioOutputSnapshot: Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
}

/// Public Core Audio listener for the system's default output route. It observes
/// only device identity/name and never captures or inspects audio data.
@MainActor
final class AudioOutputService {
    var onChange: ((AudioOutputSnapshot) -> Void)?

    private let listenerQueue = DispatchQueue(label: "app.topside.audio-output", qos: .utility)
    private var listener: AudioObjectPropertyListenerBlock?

    func start() {
        guard listener == nil else { return }
        var address = Self.defaultOutputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, listenerQueue, block
        )
        guard status == noErr else {
            Log.info("audio output listener failed status=\(status)")
            return
        }
        listener = block
        refresh()
    }

    private func refresh() {
        guard let id = Self.defaultOutputDevice(), id != kAudioObjectUnknown else { return }
        onChange?(AudioOutputSnapshot(id: id, name: Self.deviceName(id) ?? "Unknown output"))
    }

    nonisolated private static var defaultOutputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    nonisolated private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = defaultOutputAddress
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )
        return status == noErr ? id : nil
    }

    nonisolated private static func deviceName(_ id: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        return status == noErr ? value as String : nil
    }
}
