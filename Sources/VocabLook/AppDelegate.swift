import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let coordinator = CaptureCoordinator(appState: appState)
        coordinator.start()
        self.coordinator = coordinator

        Reminder.shared.configure()

        if !Settings.didOnboard || !Permissions.isAccessibilityTrusted() {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .openOnboarding, object: nil)
            }
        }
    }
}
