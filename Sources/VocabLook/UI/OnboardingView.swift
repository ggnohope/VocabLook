import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trusted = Permissions.isAccessibilityTrusted()

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed.fill").font(.system(size: 34)).foregroundStyle(.tint)
            Text("One quick permission").font(.system(size: 19, weight: .semibold))
            Text("To read the word you look up, VocabLook needs macOS Accessibility access. It only reads the selection when you press ⌃⌘D.")
                .font(.system(size: 13.5)).foregroundColor(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open System Settings → Privacy & Security → Accessibility")
                step(2, "Turn on VocabLook")
                step(3, "Look up a word to test it")
            }
            .padding(.vertical, 4)

            HStack {
                Button("Open System Settings") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(.borderedProminent)
                Button(trusted ? "Done ✓" : "I've enabled it") {
                    trusted = Permissions.isAccessibilityTrusted()
                    Settings.didOnboard = true
                    if trusted { dismiss() }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(30)
        .frame(width: 440)
        .tint(Color.inkIndigo)
        .onAppear { _ = Permissions.promptAccessibility() }
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 11) {
            Text("\(n)").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                .frame(width: 22, height: 22).background(Color.inkIndigo, in: Circle())
            Text(text).font(.system(size: 13))
            Spacer()
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
    }
}
