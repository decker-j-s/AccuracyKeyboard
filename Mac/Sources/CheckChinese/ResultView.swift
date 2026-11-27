import SwiftUI

// The Mac result window. Same look as the iPhone keyboard (CheckView.swift),
// laid out for a small window: cards, red/green changes, pinyin, speak buttons.
struct ResultView: View {
    @ObservedObject var model: CheckModel
    let onCopy: (String) -> Void
    let onClose: () -> Void

    // A light tint of the text color: a lighter gray in dark mode, a slightly
    // darker gray in light mode, so cards always stand out from the window.
    private let cardColor = Color.primary.opacity(0.07)

    var body: some View {
        VStack(spacing: 10) {
            content
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            buttons
        }
        .padding(14)
        .padding(.top, 18)   // room for the transparent title bar
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.spring(duration: 0.35), value: model.state)
    }

    // MARK: - One look per state

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            centeredCard {
                Image(systemName: "ellipsis")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.secondary)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                Text("检查中…").foregroundStyle(.secondary)
                Text(model.original).font(.title3).padding(.top, 4)
            }

        case .natural:
            centeredCard {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.green)
                    .frame(width: 50, height: 50)
                    .background(.green.opacity(0.15), in: Circle())
                Text("很自然！").font(.title3.weight(.semibold))
                Text("Sounds natural. Send it.").foregroundStyle(.secondary)
                HStack {
                    Text(model.original).font(.title3)
                    speakButton(model.original)
                }
                .padding(.top, 4)
            }

        case .failed(let message):
            centeredCard {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24))
                    .foregroundStyle(.red)
                Text(message)
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
                    speakButton(result.corrected)
                }
                trackedChanges(diffSegments(original: model.original, corrected: result.corrected))
                    .font(.title2)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))

            ForEach(result.displayChanges, id: \.self) { change in
                // Short changes (不 → 没): reason beside them. Long phrases:
                // reason underneath, so it doesn't get squeezed into a thin column.
                let isShort = change.from.count + change.to.count <= 6
                let layout = isShort ? AnyLayout(HStackLayout(spacing: 10))
                                     : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                layout {
                    HStack(spacing: 6) {
                        charsWithPinyin(change.from, color: .red)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                        charsWithPinyin(change.to, color: .green)
                    }
                    .fixedSize()
                    Text(change.reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
            }

            if !result.nativeVersion.isEmpty && result.nativeVersion != result.corrected {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Native speaker", systemImage: "person.wave.2")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(result.nativeVersion).textSelection(.enabled)
                        Text(pinyin(result.nativeVersion))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    speakButton(result.nativeVersion)
                    Button("Use this") { onCopy(result.nativeVersion) }
                        .buttonStyle(.bordered)
                        .tint(.green)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Buttons

    private var buttons: some View {
        HStack {
            if case .suggestion = model.state {
                Text("Return to replace · Esc to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)          // Esc
            if case .suggestion(let result) = model.state {
                Button("Replace") { onCopy(result.corrected) }
                    .keyboardShortcut(.defaultAction)     // Return
                    .tint(.green)
            }
        }
        .controlSize(.large)
    }

    // MARK: - Helpers

    private func speakButton(_ text: String) -> some View {
        Button { model.speak(text) } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.footnote)
                .frame(width: 26, height: 26)
                .background(.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Play pronunciation")
    }

    private func charsWithPinyin(_ text: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(text.isEmpty ? "—" : text)
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
            if containsChinese(text) {   // no pinyin under English like "sign up"
                Text(pinyin(text)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func centeredCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 8, content: content)
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(14)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
    }

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
            }
            line += piece
        }
        return Text(line)
    }
}
