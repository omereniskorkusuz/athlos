import AppKit
import Carbon.HIToolbox

/// Global shortcut (default ⌃⌥Space). Carbon `RegisterEventHotKey` needs no accessibility permission.
@MainActor
final class HotKeyService {
    /// Kept static because the C callback can't capture context.
    nonisolated(unsafe) private static var handler: (@MainActor () -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func register(keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey, action: @escaping @MainActor () -> Void) {
        unregister()
        Self.handler = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyService.handler?() }
            }
            return noErr
        }, 1, &spec, nil, &eventHandler)

        let id = EventHotKeyID(signature: OSType(0x4154_4C53), id: 1) // 'ATLS'
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
        Self.handler = nil
    }
}
