import SwiftUI

/// The "Saved <term>" toast content. Pure view; the panel is managed by HUDController.
struct CaptureHUD: View {
    let term: String
    let subtitle: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(Color.green)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundColor(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("Saved ").font(.system(size: 14)) + Text(term).font(.system(size: 14, weight: .semibold, design: .serif))
                Text(subtitle).font(.system(size: 11.5)).foregroundColor(.secondary)
            }

            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
