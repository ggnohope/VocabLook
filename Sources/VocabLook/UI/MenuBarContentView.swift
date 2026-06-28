import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            dueCard
            statsRow
            Divider()
            recentList
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { app.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .openReviewWindow)) { _ in
            openWindow(id: "review")
            NSApp.activate(ignoringOtherApps: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openOnboarding)) { _ in
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "book.closed.fill").foregroundStyle(.tint)
            Text("VocabLook").font(.system(size: 14, weight: .semibold))
            Spacer()
            if app.streak > 0 {
                Text("🔥 \(app.streak)").font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
            }
            Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                .buttonStyle(.plain).foregroundColor(.secondary)
        }
    }

    private var dueCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(app.dueCount)").font(.system(size: 26, weight: .bold))
                Text("words due today").font(.system(size: 11.5)).opacity(0.85)
            }
            Spacer()
            Button("Start review →") {
                openWindow(id: "review")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderedProminent)
            .disabled(app.dueCount == 0)
        }
        .padding(14)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
        .foregroundColor(.white)
    }

    private var statsRow: some View {
        HStack {
            stat("\(app.capturedToday)", "new today")
            Spacer()
            stat("\(app.totalLearned)", "learned")
            Spacer()
            stat(app.recallPercent.map { "\($0)%" } ?? "—", "recall")
        }
        .font(.system(size: 11.5)).foregroundColor(.secondary)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value).foregroundColor(.primary).fontWeight(.semibold)
            Text(label)
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 2) {
            if app.recents.isEmpty {
                Text("No words yet today. Press ⌃⌘D on any word to capture it.")
                    .font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(app.recents) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(entry.term).font(.system(size: 14, weight: .medium, design: .serif))
                        Text(entry.sourceApp ?? "").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text(Self.timeFmt.string(from: entry.createdAt))
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("History") { openWindow(id: "review") }.buttonStyle(.bordered).disabled(true)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.bordered)
        }
        .controlSize(.small)
    }
}
