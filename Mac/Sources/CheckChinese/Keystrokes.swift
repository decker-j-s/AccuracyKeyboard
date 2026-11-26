import AppKit
import Carbon

// Presses ⌘-shortcuts for you (⌘A, ⌘C, ⌘V) in whatever app is in front.
// macOS only allows this after you turn on Accuracy Checker in
// System Settings › Privacy & Security › Accessibility.
enum Keystrokes {
    static var allowed: Bool { AXIsProcessTrusted() }

    /// Shows Apple's "allow this app" prompt (only if not allowed yet).
    static func askForPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func selectAll() { pressCommand(kVK_ANSI_A) }
    static func copy()      { pressCommand(kVK_ANSI_C) }
    static func paste()     { pressCommand(kVK_ANSI_V) }

    // Sends key-down then key-up with only ⌘ held, ignoring any keys
    // you're still physically holding from the shortcut.
    private static func pressCommand(_ key: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

// Small helper so the steps below read in order: do this, wait, do that.
func after(_ seconds: Double, _ work: @escaping () -> Void) {
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
}
