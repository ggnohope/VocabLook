import AppKit
import SwiftUI

/// Opens the app's auxiliary windows as AppKit-hosted NSWindows. This (rather than SwiftUI `Window`
/// scenes) is required for a menu-bar (`.accessory`) app so windows reliably appear on the user's
/// CURRENT Space — `collectionBehavior = .moveToActiveSpace` plus `NSApp.activate`. It also lets us
/// open a fresh review window with a chosen scope and open windows from non-UI code (notifications).
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    /// The shared app state, injected at launch so hosted views observe the same instance.
    var appState: AppState?

    private var windows: [String: NSWindow] = [:]

    func showReview(scope: ReviewSession.Scope) {
        // Always recreate so the session reloads the correct cards for this scope.
        present(id: "review", title: "Review", fresh: true) { close in
            AnyView(ReviewView(scope: scope, onClose: close))
        }
    }

    func showSettings() {
        present(id: "settings", title: "Settings") { _ in AnyView(SettingsView()) }
    }

    func showOnboarding() {
        present(id: "onboarding", title: "Welcome to VocabLook") { close in
            AnyView(OnboardingView(onClose: close))
        }
    }

    private func present(id: String, title: String, fresh: Bool = false,
                         content: (@escaping () -> Void) -> AnyView) {
        NSApp.activate(ignoringOtherApps: true)

        if fresh, let existing = windows[id] {
            existing.close()
            windows[id] = nil
        }
        if let existing = windows[id] {
            existing.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            existing.center()
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let close: () -> Void = { [weak self] in
            self?.windows[id]?.close()
            self?.windows[id] = nil
        }
        let root = content(close).environmentObject(appState ?? AppState())
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
    }
}
