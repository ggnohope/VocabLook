import AppKit
import SwiftUI

/// Shows a borderless, non-activating floating panel near the bottom of the active screen.
final class HUDController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?

    func show(term: String, subtitle: String, onUndo: @escaping () -> Void) {
        dismiss()

        let hud = CaptureHUD(term: term, subtitle: subtitle) { [weak self] in
            onUndo()
            self?.dismiss()
        }
        let hosting = NSHostingView(rootView: hud)
        hosting.frame = NSRect(x: 0, y: 0, width: 320, height: 60)

        let panel = NSPanel(contentRect: hosting.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 160
            let y = frame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        let work = DispatchWorkItem { [weak self] in self?.dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
