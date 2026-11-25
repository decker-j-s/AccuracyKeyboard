import UIKit
import SwiftUI

// iOS creates this class when the user switches to the keyboard.
// It owns `textDocumentProxy`, the keyboard's only connection to the
// text field in the other app (iMessage, WeChat, …).
class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()

    override func viewDidLoad() {
        super.viewDidLoad()

        let checkView = CheckView(
            model: model,
            // Only show 🌐 if the iPhone doesn't already show one below the keyboard.
            showGlobe: needsInputModeSwitchKey,
            onGlobe: { [weak self] in self?.advanceToNextInputMode() },
            onCheck: { [weak self] in self?.check() },
            onReplace: { [weak self] text in self?.replace(with: text) },
            onUndo: { [weak self] previous in self?.undo(to: previous) }
        )

        // Put the SwiftUI view inside this UIKit controller.
        let host = UIHostingController(rootView: checkView)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: 280),
        ])
        host.didMove(toParent: self)
    }

    // The whole message = text before the cursor + text after it.
    // Note: some apps only share part of a very long message.
    private func currentText() -> String {
        let proxy = textDocumentProxy
        return (proxy.documentContextBeforeInput ?? "") + (proxy.documentContextAfterInput ?? "")
    }

    private func check() {
        let text = currentText().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            model.state = .failed("The message is empty.")
            return
        }
        // Without Full Access, iOS blocks all network calls from keyboards.
        guard hasFullAccess else {
            model.state = .failed(ClaudeClient.CheckError.noFullAccess.errorDescription!)
            return
        }

        model.original = text
        model.state = .checking

        // `Task` runs the network call in the background; `@MainActor`
        // brings us back to the main thread to update the screen.
        Task { @MainActor in
            do {
                let result = try await ClaudeClient.check(text)
                model.state = result.isNatural(original: text) ? .natural : .suggestion(result)
            } catch {
                model.state = .failed(error.localizedDescription)
            }
        }
    }

    // Replace: remember exactly what was there (for Undo), then swap in the new text.
    private func replace(with newText: String) {
        let previous = currentText()
        swapText(to: newText)
        model.state = .replaced(previous: previous)
    }

    // Undo: put the user's original message back.
    private func undo(to previous: String) {
        swapText(to: previous)
        model.state = .idle
    }

    // Moves the cursor to the end, deletes the whole message one character
    // at a time (the only way a keyboard can delete), then types the new one.
    private func swapText(to newText: String) {
        let proxy = textDocumentProxy
        let before = proxy.documentContextBeforeInput ?? ""
        let after = proxy.documentContextAfterInput ?? ""
        // Count first: the proxy can take a moment to catch up after the cursor moves.
        let total = before.count + after.count

        proxy.adjustTextPosition(byCharacterOffset: after.count)
        for _ in 0..<total { proxy.deleteBackward() }
        proxy.insertText(newText)
    }
}
