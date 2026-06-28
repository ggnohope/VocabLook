import AppKit
import ApplicationServices
import CoreGraphics
import UserNotifications

enum Permissions {
    /// Whether the app is trusted for Accessibility (needed for reading AXSelectedText + posting events).
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Whether the app has Input Monitoring access — REQUIRED for the global keyDown monitor to
    /// receive Ctrl+Cmd+D (macOS 10.15+ routes global keystroke monitoring through this service).
    static func isInputMonitoringTrusted() -> Bool {
        CGPreflightListenEventAccess()
    }

    /// Prompts for Input Monitoring access (shows the system dialog) and returns the current state.
    @discardableResult
    static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    /// Opens System Settings directly at the Input Monitoring pane.
    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Prompts for Accessibility access (shows the system dialog) and returns the current state.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly at the Accessibility pane.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func requestNotifications(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
}
