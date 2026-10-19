import Carbon.HIToolbox
import Foundation

enum GlobalShortcut: String, CaseIterable, Identifiable {
    case off
    case optionSpace
    case controlOptionSpace
    case commandShiftSpace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .optionSpace: return "⌥ Space"
        case .controlOptionSpace: return "⌃⌥ Space"
        case .commandShiftSpace: return "⇧⌘ Space"
        }
    }

    fileprivate var modifiers: UInt32 {
        switch self {
        case .off: return 0
        case .optionSpace: return UInt32(optionKey)
        case .controlOptionSpace: return UInt32(controlKey | optionKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        }
    }
}

private let topsideHotKeyHandler: EventHandlerUPP = { _, _, userData in
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let service = Unmanaged<GlobalHotKeyService>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in service.fire() }
    return noErr
}

@MainActor
final class GlobalHotKeyService {
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), topsideHotKeyHandler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    func update(_ shortcut: GlobalShortcut) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        guard shortcut != .off else { return }
        var newHotKey: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x54505344), id: 1) // TPSD
        let status = RegisterEventHotKey(UInt32(kVK_Space), shortcut.modifiers, identifier,
                                         GetApplicationEventTarget(), 0, &newHotKey)
        if status == noErr {
            hotKey = newHotKey
            Log.info("globalShortcut=\(shortcut.rawValue)")
        } else {
            Log.info("globalShortcut registration failed status=\(status)")
        }
    }

    fileprivate func fire() { onPress?() }
}
