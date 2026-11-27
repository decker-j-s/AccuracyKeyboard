import UIKit
import SwiftUI
import Combine

// iOS creates this class when the user switches to the keyboard.
// It owns `textDocumentProxy`, the keyboard's only connection to the
// text field in the other app (iMessage, WeChat, …).
class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var heightConstraint: NSLayoutConstraint?
    private var stateWatcher: AnyCancellable?   // keeps the height in sync with the state

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
        let height = view.heightAnchor.constraint(equalToConstant: 280)
        heightConstraint = height
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            height,
        ])
        host.didMove(toParent: self)

        // Whenever the result changes, resize the keyboard to fit it.
        stateWatcher = model.$state.sink { [weak self] state in
            self?.heightConstraint?.constant = Self.height(for: state)
        }
    }

    // How tall the keyboard should be for what it's showing.
    // Compact for simple screens; taller for corrections, so the
    // change cards and the "Native speaker" card fit without scrolling.
    private static func height(for state: KeyboardModel.State) -> CGFloat {
        guard case .suggestion(let result) = state else { return 280 }
        let sentenceIsLong = result.corrected.count > 20
        var height: CGFloat = sentenceIsLong ? 240 : 215   // badge + sentence card + buttons
        for change in result.displayChanges {               // one card per change, by size
            switch change.size {
            case .tiny:   height += 70
            case .medium: height += 95
            case .long:   height += 135
            }
        }
        if !result.nativeVersion.isEmpty && result.nativeVersion != result.corrected {
            height += 86                                    // native speaker card (sentence + pinyin)
        }
        // Never more than about half the screen: past this it would cover your
        // chat, so the result scrolls inside the keyboard instead.
        return min(height, 400)
    }

    // The full message exactly as it was read when Check was tapped
    // (including any spaces), so Replace knows how much to delete.
    private var messageInBox = ""
    // How many characters Replace typed, so Undo knows how much to delete.
    private var insertedCount = 0

    // Reads the WHOLE message. iOS only shows a keyboard the text just before
    // the cursor (in Messages, often only the last sentence or two). So we
    // walk the cursor backwards one visible chunk at a time, collecting the
    // earlier text, until there's nothing left before it. Then we put the
    // cursor back where it was.
    private func readWholeMessage() async -> String {
        let proxy = textDocumentProxy
        let after = proxy.documentContextAfterInput ?? ""
        var chunk = proxy.documentContextBeforeInput ?? ""
        var collected = chunk
        var moved = 0

        // Stop at the start of the message, or after ~3,000 characters to be safe.
        while !chunk.isEmpty && moved < 3000 {
            proxy.adjustTextPosition(byCharacterOffset: -chunk.count)
            moved += chunk.count
            // The text box needs a moment to report the new text before the cursor.
            try? await Task.sleep(nanoseconds: 80_000_000)   // 0.08 s
            chunk = proxy.documentContextBeforeInput ?? ""
            collected = chunk + collected
        }

        proxy.adjustTextPosition(byCharacterOffset: moved)   // cursor back where it was
        try? await Task.sleep(nanoseconds: 80_000_000)
        return collected + after
    }

    private func check() {
        // Without Full Access, iOS blocks all network calls from keyboards.
        guard hasFullAccess else {
            model.state = .failed(ClaudeClient.CheckError.noFullAccess.errorDescription!)
            return
        }
        model.state = .checking

        // `Task` runs the work in the background; `@MainActor` keeps the
        // screen updates on the main thread.
        Task { @MainActor in
            let whole = await readWholeMessage()
            let text = whole.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                model.state = .failed("The message is empty.")
                return
            }
            messageInBox = whole
            model.original = text
            do {
                let result = try await ClaudeClient.check(text)
                model.state = result.isNatural(original: text) ? .natural : .suggestion(result)
            } catch {
                model.state = .failed(error.localizedDescription)
            }
        }
    }

    // Replace: swap the whole message for the new text, and remember the
    // original so Undo can bring it back.
    private func replace(with newText: String) {
        let previous = messageInBox
        swapText(deleting: messageInBox.count, insert: newText)
        insertedCount = newText.count
        model.state = .replaced(previous: previous)
    }

    // Undo: delete what Replace typed and put the original message back.
    private func undo(to previous: String) {
        swapText(deleting: insertedCount, insert: previous)
        messageInBox = previous
        model.state = .idle
    }

    // Moves the cursor to the end of the message, deletes `count` characters
    // one at a time (the only way a keyboard can delete), then types the new
    // text. deleteBackward works even on text the keyboard can't "see".
    private func swapText(deleting count: Int, insert newText: String) {
        let proxy = textDocumentProxy
        proxy.adjustTextPosition(byCharacterOffset: (proxy.documentContextAfterInput ?? "").count)
        for _ in 0..<count { proxy.deleteBackward() }
        proxy.insertText(newText)
    }
}
