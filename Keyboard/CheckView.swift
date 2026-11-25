import SwiftUI
import Combine   // provides ObservableObject and @Published

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
        case failed(String)
    }

    @Published var state: State = .idle
    var original = ""   // the message as it was when the user tapped Check
}

struct CheckView: View {
    @ObservedObject var model: KeyboardModel
    let showGlobe: Bool
    let onGlobe: () -> Void
    let onCheck: () -> Void
    let onReplace: (String) -> Void

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
                    Text(result.changes.count == 1 ? "1 change" : "\(result.changes.count) changes")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                trackedChanges(diffSegments(original: model.original, corrected: result.corrected))
                    .font(.title2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 14))

            // One small card per change: 不 bù → 没 méi + the reason
            ForEach(result.changes, id: \.self) { change in
                changeRow(change)
            }

            if !result.nativeVersion.isEmpty && result.nativeVersion != result.corrected {
                Label("Native: \(result.nativeVersion)", systemImage: "person.wave.2")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func changeRow(_ change: CheckResult.Change) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 6) {
                charsWithPinyin(change.from, color: .red)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                charsWithPinyin(change.to, color: .green)
            }
            .fixedSize()
            Text(change.reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(cardColor, in: RoundedRectangle(cornerRadius: 14))
    }

    // Characters on top, pinyin underneath. "—" if nothing was there.
    private func charsWithPinyin(_ text: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(text.isEmpty ? "—" : text)
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
            if !text.isEmpty {
                Text(pinyin(text))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
        }
        .font(.body.weight(.medium))
    }

    // MARK: - Helpers

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
