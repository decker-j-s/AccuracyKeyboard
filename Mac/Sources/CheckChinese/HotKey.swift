import Carbon

// A system-wide keyboard shortcut. Works in every app, and needs no
// special permission just to listen for it.
//
// Uses Apple's older "Carbon" API because it's still the simplest way
// to register a global hotkey on macOS.
final class HotKey {
    private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    /// keyCode: which key (e.g. kVK_ANSI_C). modifiers: e.g. controlKey | optionKey.
    init(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        HotKey.action = action

        // When any of our hotkeys is pressed, run `action`.
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &eventType, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x43484E5A), id: 1)   // "CHNZ"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id,
                            GetApplicationEventTarget(), 0, &ref)
    }
}
