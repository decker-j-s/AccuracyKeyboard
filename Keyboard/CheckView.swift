import SwiftUI
import Combine       // provides ObservableObject and @Published
import AVFoundation  // the iPhone's built-in text-to-speech

// Everything the keyboard shows. SwiftUI redraws the view automatically
// whenever one of the @Published values in KeyboardModel changes.
final class KeyboardModel: ObservableObject {
    // `Equatable` lets SwiftUI tell when the state changed, so it knows
    // when to animate and when to buzz.
    enum State: Equatable {
        case idle
        case checking
        case natural
        case suggestion(CheckResult)
        case replaced(previous: String)   // after Replace; `previous` is what Undo restores
        case failed(String)
    }

    @Published var state: State = .idle
    var original = ""   // the message as it was when the user tapped Check

    // Kept here (not inside `speak`) so it isn't thrown away mid-sentence.
    private let speaker = AVSpeechSynthesizer()

    // Reads Chinese text aloud with a Mandarin voice. Works offline.
    func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9   // a touch slower for learning
        speaker.speak(utterance)
    }
}

struct CheckView: View {
    @ObservedObject var model: KeyboardModel
    let showGlobe: Bool
    let onGlobe: () -> Void
    let onCheck: () -> Void
    let onReplace: (String) -> Void   // swap in corrected (or native) text
    let onUndo: (String) -> Void      // put back what the user had typed

    // Card color: white in light mode, dark gray in dark mode.
    private let cardColor = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        VStack(spacing: 10) {
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    // A new `id` per state makes SwiftUI treat each result as a
                    // fresh view, so the transition above plays every time.
                    .id(stateID)
            }
            buttons
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .animation(.spring(duration: 0.35), value: model.state)
        // A small vibration when a result arrives.
        .sensoryFeedback(trigger: model.state) { _, new in
            switch new {
            case .natural: return .success
            case .suggestion: return .warning
            case .failed: return .error
            default: return nil
            }
        }
    }

    private var stateID: String {
        switch model.state {
        case .idle: return "idle"
        case .checking: return "checking"
        case .natural: return "natural"
        case .suggestion(let r): return "suggestion-\(r.corrected)"
        case .replaced: return "replaced"
        case .failed(let m): return "failed-\(m)"
        }
    }

    // MARK: - The main area, one look per state

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            centeredCard {
                Image(systemName: "text.bubble")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Type with the Chinese keyboard,\nthen come back and tap Check.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .checking:
            centeredCard {
                // An SF Symbol with a built-in "pulsing dots" animation.
                Image(systemName: "ellipsis")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("检查中…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .natural:
            centeredCard {
                Image(systemName: "checkmark")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 54, height: 54)
                    .background(.green.opacity(0.15), in: Circle())
                    .transition(.scale)
                Text("很自然！")
                    .font(.title3.weight(.semibold))
                Text("Sounds natural. Send it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                speakButton(model.original)
            }

        case .replaced:
            centeredCard {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.green)
                Text("已替换")
                    .font(.title3.weight(.semibold))
                Text("Tap Undo to bring back what you wrote.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            centeredCard {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .suggestion(let result):
            suggestion(result)
        }
    }

    private func suggestion(_ result: CheckResult) -> some View {
        let isError = result.verdict == "error"
        let color: Color = isError ? .red : .orange

        return VStack(spacing: 8) {
            // Card 1: badge + the message with tracked changes
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(isError ? "有错" : "不太自然",
                          systemImage: isError ? "exclamationmark.triangle.fill" : "lightbulb.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(color.opacity(0.15), in: Capsule())
                    Spacer()
                    Text(result.displayChanges.count == 1 ? "1 change" : "\(result.displayChanges.count) changes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    speakButton(result.corrected)
                }
                trackedChanges(diffSegments(original: model.original, corrected: result.corrected))
                    .font(sentenceFont(for: result))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14))

            // One small card per change: 不 bù → 没 méi + the reason
            ForEach(result.displayChanges, id: \.self) { change in
                changeRow(change)
            }

            // How a native speaker might say it, with buttons to hear it or send it instead.
            if !result.nativeVersion.isEmpty && result.nativeVersion != result.corrected {
                nativeCard(result.nativeVersion)
            }
        }
    }

    // How a native speaker might say it, with buttons to hear it or send it instead.
    // Short sentence: buttons beside it. Long sentence: the text gets the full
    // width and the buttons go underneath, so it doesn't turn into a thin column.
    @ViewBuilder
    private func nativeCard(_ native: String) -> some View {
        let isLong = native.count > 15
        let text = VStack(alignment: .leading, spacing: 2) {
            Label("Native speaker", systemImage: "person.wave.2")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(native)
                .font(isLong ? .callout : .body)
                .fixedSize(horizontal: false, vertical: true)
            Text(pinyin(native))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        let buttons = HStack(spacing: 10) {
            speakButton(native)
            Button("Use this") { onReplace(native) }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.green.opacity(0.15), in: Capsule())
                .foregroundStyle(.green)
                .buttonStyle(.plain)
        }

        Group {
            if isLong {
                VStack(alignment: .leading, spacing: 8) { text; buttons }
            } else {
                HStack(spacing: 10) { text; buttons }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // The main sentence gets smaller as the message gets longer, so a long
    // correction stays readable instead of becoming a wall of big text.
    private func sentenceFont(for result: CheckResult) -> Font {
        let length = max(model.original.count, result.corrected.count)
        if length <= 20 { return .title2 }
        if length <= 45 { return .title3 }
        return .body
    }

    // One card per change, laid out by size (see Change.size in CheckResult.swift).
    @ViewBuilder
    private func changeRow(_ change: CheckResult.Change) -> some View {
        let reason = Text(change.reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

        Group {
            switch change.size {
            case .tiny:      // 不 → 没   reason beside it
                HStack(spacing: 10) {
                    sideBySide(change)
                    reason
                }
            case .medium:    // 去中国在明年 → 明年去中国, reason below
                VStack(alignment: .leading, spacing: 6) {
                    sideBySide(change)
                    reason
                }
            case .long:      // long English phrase: stacked so everything wraps
                VStack(alignment: .leading, spacing: 4) {
                    charsWithPinyin(change.from, color: .red, size: .long)
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    charsWithPinyin(change.to, color: .green, size: .long)
                    reason.padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // Old → new on one line (only used when both are short).
    private func sideBySide(_ change: CheckResult.Change) -> some View {
        HStack(spacing: 6) {
            charsWithPinyin(change.from, color: .red)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
            charsWithPinyin(change.to, color: .green)
        }
        .fixedSize()
    }

    // Characters with pinyin underneath. "—" if nothing was there.
    // Long text uses a smaller font, left-aligned, and is allowed to wrap.
    private func charsWithPinyin(_ text: String, color: Color,
                                 size: CheckResult.Change.Size = .tiny) -> some View {
        let isLong = size == .long
        return VStack(alignment: isLong ? .leading : .center, spacing: 1) {
            Text(text.isEmpty ? "—" : text)
                .font(isLong ? .body.weight(.medium) : .title3.weight(.medium))
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            if containsChinese(text) {   // no pinyin under English like "sign up"
                Text(pinyin(text))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack(spacing: 8) {
            if showGlobe {
                Button(action: onGlobe) {
                    Image(systemName: "globe")
                        .frame(width: 44, height: 42)
                }
                .buttonStyle(KeyStyle(fill: cardColor))
            }

            Button(action: onCheck) {
                Label("Check", systemImage: "sparkles")
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(KeyStyle(fill: cardColor))
            .disabled(model.state == .checking)

            if case .suggestion(let result) = model.state {
                Button { onReplace(result.corrected) } label: {
                    Label("Replace", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(KeyStyle(fill: .green, text: .white))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            if case .replaced(let previous) = model.state {
                Button { onUndo(previous) } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
                .buttonStyle(KeyStyle(fill: cardColor))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .font(.body.weight(.medium))
    }

    // MARK: - Helpers

    // Small round 🔊 button that reads `text` aloud.
    private func speakButton(_ text: String) -> some View {
        Button { model.speak(text) } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.footnote)
                .frame(width: 30, height: 30)
                .background(.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Play pronunciation")
    }

    // A rounded card with its contents stacked and centered.
    private func centeredCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8, content: content)
            .frame(maxWidth: .infinity, minHeight: 150)
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // Builds one line of text: red strikethrough with a pink highlight for
    // deletions, green with a light green highlight for additions.
    // AttributedString = one string where each piece can have its own style.
    private func trackedChanges(_ segments: [DiffSegment]) -> Text {
        var line = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .removed:
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
                piece.backgroundColor = .red.opacity(0.15)
            case .added:
                piece.foregroundColor = .green
                piece.backgroundColor = .green.opacity(0.15)
                piece.font = .title2.weight(.semibold)
            }
            line += piece
        }
        return Text(line)
    }
}

// Rounded, key-like buttons that shrink slightly while pressed.
struct KeyStyle: ButtonStyle {
    var fill: Color
    var text: Color = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? text : .secondary)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
