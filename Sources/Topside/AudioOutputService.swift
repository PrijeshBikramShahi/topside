import CoreAudio
import Foundation
import TopsideCore

struct AudioOutputSnapshot: Equatable, Sendable {
    let id: AudioDeviceID
    let name: String
    let transport: AudioTransport
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
        onChange?(AudioOutputSnapshot(id: id, name: Self.deviceName(id) ?? "Unknown output",
                                      transport: Self.transport(id)))
    }

    /// Every device that can play audio, sorted by name. Public Core Audio only.
    nonisolated static func outputDevices() -> [AudioOutputSnapshot] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter(hasOutputChannels).map {
            AudioOutputSnapshot(id: $0, name: deviceName($0) ?? "Unknown output", transport: transport($0))
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func currentOutputID() -> AudioDeviceID? { defaultOutputDevice() }

    /// Makes `id` the default output (and the system-sound output, as the Sound settings pane does).
    @discardableResult
    nonisolated static func setDefaultOutput(_ id: AudioDeviceID) -> Bool {
        var device = id
        var allSucceeded = true
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                                                    UInt32(MemoryLayout<AudioDeviceID>.size), &device)
            if status != noErr { allSucceeded = false; Log.info("set default output failed status=\(status)") }
        }
        return allSucceeded
    }

    nonisolated private static func hasOutputChannels(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
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

    nonisolated private static func transport(_ id: AudioDeviceID) -> AudioTransport {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var code: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &code) == noErr else { return .other }
        switch code {
        case UInt32(kAudioDeviceTransportTypeBuiltIn): return .builtIn
        case UInt32(kAudioDeviceTransportTypeBluetooth), UInt32(kAudioDeviceTransportTypeBluetoothLE): return .bluetooth
        case UInt32(kAudioDeviceTransportTypeUSB): return .usb
        case UInt32(kAudioDeviceTransportTypeAirPlay): return .airPlay
        case UInt32(kAudioDeviceTransportTypeHDMI), UInt32(kAudioDeviceTransportTypeDisplayPort): return .display
        case UInt32(kAudioDeviceTransportTypeVirtual), UInt32(kAudioDeviceTransportTypeAggregate): return .virtual
        default: return .other
        }
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
