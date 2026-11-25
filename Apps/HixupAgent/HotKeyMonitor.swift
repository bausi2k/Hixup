import Carbon.HIToolbox
import Foundation

/// Globaler Hotkey (Carbon `RegisterEventHotKey`): braucht keine Berechtigung und funktioniert ohne Sandbox.
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Returns: `nil`, wenn die Tastenkombination nicht registriert werden konnte (z. B. schon belegt).
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue().action()
                return noErr
            },
            1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x48584950), id: 1) // 'HXIP'
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
