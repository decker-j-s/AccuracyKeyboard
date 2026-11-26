import AppKit
import SwiftUI
import Combine
import AVFoundation

// The Mac's version of KeyboardModel: what the result window is showing.
final class CheckModel: ObservableObject {
    enum State: Equatable {
        case checking
        case natural
        case suggestion(CheckResult)
        case failed(String)
    }

    @Published var state: State = .checking
    var original = ""

    private let speaker = AVSpeechSynthesizer()

    func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        speaker.speak(utterance)
    }
}

// A small floating window that shows one check at a time.
final class ResultWindow {
    private let model = CheckModel()
    private var panel: NSPanel?
    private var hostingView: NSHostingView<ResultView>?
    private var stateWatcher: AnyCancellable?        // resizes the window when the result changes
    private var previousApp: NSRunningApplication?   // the chat app to paste back into

    // Shortcut flow: select the message you're typing (⌘A), copy it (⌘C),
    // put your clipboard back the way it was, then check the text.
    func checkMessageInFrontApp() {
        guard Keystrokes.allowed else {
            Keystrokes.askForPermission()
            show(error: "Allow Accuracy Checker in System Settings › Privacy & Security › Accessibility, then press the shortcut again.")
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let clipboard = NSPasteboard.general
        let saved = clipboard.string(forType: .string)
        let before = clipboard.changeCount

        after(0.15) {                          // let you release the shortcut keys
            Keystrokes.selectAll()
            Keystrokes.copy()
            after(0.25) {                      // give the app a moment to copy
                let text = clipboard.changeCount != before ? clipboard.string(forType: .string) : nil
                Self.restore(saved)
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.show(error: "Couldn't find a message. Click in the message box first, then press the shortcut.")
                    return
                }
                self.check(text)
            }
        }
    }

    // Right-click › Services flow (text already selected), and the shared path for both.
    func check(_ text: String) {
        if previousApp == nil || previousApp == NSRunningApplication.current {
            previousApp = NSWorkspace.shared.frontmostApplication
        }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        model.original = message
        model.state = .checking
        show()

        // Same call as the iPhone keyboard (ClaudeClient.swift is shared).
        Task { @MainActor in
            do {
                let result = try await ClaudeClient.check(message)
                model.state = result.isNatural(original: message) ? .natural : .suggestion(result)
            } catch {
                model.state = .failed(error.localizedDescription)
            }
        }
    }

    private func show(error: String) {
        model.original = ""
        model.state = .failed(error)
        show()
    }

    private func show() {
        if panel == nil {
            let view = ResultView(model: model,
                                  onCopy: { [weak self] text in self?.replace(with: text) },
                                  onClose: { [weak self] in self?.close() })
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
            p.title = "Accuracy Checker"
            p.titlebarAppearsTransparent = true
            p.isMovableByWindowBackground = true
            p.level = .floating                 // stays above your chat app
            // Show up on whatever desktop Space you're on, even over full-screen apps.
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let host = NSHostingView(rootView: view)
            p.contentView = host
            p.isReleasedWhenClosed = false
            panel = p
            hostingView = host

            // Whenever the result changes, resize the window to fit it.
            stateWatcher = model.$state.sink { [weak self] _ in self?.fitToContent() }
        }
        fitToContent()
        panel?.center()
        NSApp.activate()
        panel?.makeKeyAndOrderFront(nil)
    }

    // Sizes the window to its content, keeping the top edge where it is.
    // Done a moment later (async), not mid-update: resizing while macOS is
    // still laying out the window is what caused the crash.
    private func fitToContent() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let panel = self.panel, let host = self.hostingView else { return }
            let size = host.fittingSize
            guard size.height > 0 else { return }
            var frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
            frame.origin.x = panel.frame.minX
            frame.origin.y = panel.frame.maxY - frame.height   // keep the top edge fixed
            panel.setFrame(frame, display: true, animate: false)
        }
    }

    // Replace: go back to your chat app (your message is still selected),
    // paste the fix over it, then put your clipboard back.
    private func replace(with text: String) {
        let clipboard = NSPasteboard.general
        let saved = clipboard.string(forType: .string)
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
        close()

        guard Keystrokes.allowed else { return }   // without permission: the fix is on the clipboard, press ⌘V
        after(0.25) {                              // wait for the chat app to come back to the front
            Keystrokes.paste()
            after(0.5) { Self.restore(saved) }
        }
    }

    private func close() {
        panel?.orderOut(nil)
        if let app = previousApp, app != NSRunningApplication.current {
            app.activate()
        } else {
            NSApp.hide(nil)
        }
        previousApp = nil
    }

    // Puts back whatever text was on your clipboard before.
    // (Only text is restored; if you had copied an image, it's replaced.)
    private static func restore(_ saved: String?) {
        guard let saved else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(saved, forType: .string)
    }
}
