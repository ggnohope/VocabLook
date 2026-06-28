import SwiftUI

struct ReviewView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var session = ReviewSession()
    @Environment(\.dismiss) private var dismiss
    private let pronouncer = Pronouncer()

    var body: some View {
        Group {
            if session.isFinished {
                finished
            } else if let item = session.current {
                card(item)
            }
        }
        .frame(width: 460)
        .frame(minHeight: 520)
        .background(KeyCatcher { handleKey($0) })
    }

    // MARK: - Card

    private func card(_ item: ReviewSession.Item) -> some View {
        VStack(spacing: 0) {
            progressBar
            VStack(spacing: 6) {
                if let src = item.entry.sourceApp {
                    Label(src, systemImage: "globe")
                        .font(.system(size: 11.5)).foregroundColor(.secondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .padding(.bottom, 14)
                }
                Text(item.entry.term)
                    .font(.system(size: session.revealed ? 34 : 46, weight: .semibold, design: .serif))
                if let ipa = item.entry.ipa {
                    HStack(spacing: 12) {
                        Text(ipa).font(.system(size: 15, design: .monospaced)).foregroundColor(.secondary)
                        Button { pronouncer.speak(item.entry.term) } label: {
                            Image(systemName: "speaker.wave.2.fill")
                        }.buttonStyle(.bordered).clipShape(Circle())
                    }.padding(.top, 8)
                }
                if let pos = item.entry.partOfSpeech {
                    Text(pos).font(.system(size: 14, design: .serif)).italic().foregroundColor(.secondary)
                }
            }
            .padding(.top, 14)

            if session.revealed {
                revealedContent(item)
            } else {
                Text("Press Space to reveal")
                    .font(.system(size: 12)).foregroundColor(.secondary).padding(.top, 26)
                Spacer()
            }
        }
        .padding(.horizontal, 26).padding(.bottom, 24)
    }

    private func revealedContent(_ item: ReviewSession.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().padding(.vertical, 22)
            if let def = item.entry.definition {
                Text(def).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 14)
            } else {
                Text("No dictionary definition was found — recall the meaning from memory.")
                    .font(.system(size: 14)).foregroundColor(.secondary).padding(.bottom, 14)
            }
            if let ctx = item.entry.contextText {
                contextBlock(ctx, term: item.entry.term, source: item.entry.sourceApp)
            }
            grades
            Spacer(minLength: 0)
        }
        .onAppear { if Settings.pronounceOnReveal { pronouncer.speak(item.entry.term) } }
    }

    private func contextBlock(_ ctx: String, term: String, source: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(highlight(ctx, term: term))
                .font(.system(size: 14.5, design: .serif))
            if let source { Text("— from \(source)").font(.system(size: 11)).foregroundColor(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(Rectangle().fill(Color.accentColor).frame(width: 3), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 20)
    }

    private func highlight(_ text: String, term: String) -> AttributedString {
        var attr = AttributedString(text)
        if let range = attr.range(of: term, options: .caseInsensitive) {
            attr[range].foregroundColor = .accentColor
            attr[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attr
    }

    private var grades: some View {
        HStack(spacing: 8) {
            gradeButton(.again, .red)
            gradeButton(.hard, .orange)
            gradeButton(.good, .green)
            gradeButton(.easy, .accentColor)
        }
    }

    private func gradeButton(_ grade: Grade, _ color: Color) -> some View {
        Button { apply(grade) } label: {
            VStack(spacing: 2) {
                Text(grade.label).font(.system(size: 13, weight: .semibold)).foregroundColor(color)
                Text(session.intervalPreview(grade)).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 9)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }

    private var progressBar: some View {
        HStack(spacing: 12) {
            ProgressView(value: session.progressFraction)
            Text(session.progressText).font(.system(size: 12)).foregroundColor(.secondary)
                .monospacedDigit()
        }.padding(.vertical, 16)
    }

    private var finished: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundStyle(.tint)
            Text("All done for today").font(.system(size: 19, weight: .semibold))
            Text("🔥 \(app.streak)-day streak").foregroundColor(.secondary)
            Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onAppear { app.registerReviewCompleted() }
    }

    // MARK: - Keyboard

    private func handleKey(_ key: String) {
        if !session.revealed {
            if key == " " { session.reveal() }
            return
        }
        switch key {
        case "1": apply(.again)
        case "2": apply(.hard)
        case "3": apply(.good)
        case "4": apply(.easy)
        default: break
        }
    }

    private func apply(_ grade: Grade) {
        session.grade(grade)
        app.refresh()
    }
}

/// Bridges hardware keyDown to a closure for the review window.
struct KeyCatcher: NSViewRepresentable {
    let onKey: (String) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = KeyView(); v.onKey = onKey; return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onKey: ((String) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
        override func keyDown(with event: NSEvent) {
            onKey?(event.charactersIgnoringModifiers ?? "")
        }
    }
}
