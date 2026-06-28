import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: CaptureCoordinator?
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.log("launch: accessibility=\(Permissions.isAccessibilityTrusted()) inputMonitoring=\(Permissions.isInputMonitoringTrusted()) didOnboard=\(Settings.didOnboard)")
        NSApp.setActivationPolicy(.accessory)

        WindowManager.shared.appState = appState

        let coordinator = CaptureCoordinator(appState: appState)
        coordinator.start()
        self.coordinator = coordinator

        Reminder.shared.configure()

        // Two distinct permissions are required, both requested directly here (not via the lazy
        // menu-bar UI which may not be alive at launch):
        //   • Input Monitoring  → so the global keyDown monitor RECEIVES Ctrl+Cmd+D
        //   • Accessibility     → so we can READ the selected text (AXSelectedText)
        if !Permissions.isInputMonitoringTrusted() {
            AppLog.log("requesting Input Monitoring + opening pane")
            Permissions.requestInputMonitoring()
            Permissions.openInputMonitoringSettings()
        }
        if !Permissions.isAccessibilityTrusted() {
            AppLog.log("requesting Accessibility + opening pane")
            Permissions.promptAccessibility()
            Permissions.openAccessibilitySettings()
        }
        Settings.didOnboard = true
    }
}
