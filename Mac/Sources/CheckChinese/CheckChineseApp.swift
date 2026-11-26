import AppKit
import SwiftUI
import Carbon            // key codes for the shortcut
import ServiceManagement // "open at login"

// The Mac version runs in the background (no Dock icon). macOS starts it
// when you pick "Accuracy Checker" from the right-click Services menu, and
// hands it the text you selected.

@main
enum Main {
    static let delegate = AppDelegate()   // kept here so it stays alive

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // background app: no Dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let window = ResultWindow()
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tell macOS this object answers the "Accuracy Checker" service.
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // ⌃⌥C (Control + Option + C) anywhere: check the message you're typing.
        hotKey = HotKey(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey) { [weak self] in
            self?.window.checkMessageInFrontApp()
        }

        // Start automatically when you log in, so the shortcut always works.
        // (Can be turned off in System Settings › General › Login Items.)
        try? SMAppService.mainApp.register()

        // Ask for the Accessibility permission up front (only shows if not allowed yet).
        Keystrokes.askForPermission()

        // For testing from Terminal:  CheckChinese --check "我昨天不去学校"
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--check"), i + 1 < args.count {
            window.check(args[i + 1])
        }
    }

    // Called by macOS when you choose Services › Accuracy Checker.
    // The name matches NSMessage = "checkChinese" in Info.plist.
    @objc func checkChinese(_ pasteboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some Chinese text first." as NSString
            return
        }
        window.check(text)
    }
}
