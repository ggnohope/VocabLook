import Foundation
import ServiceManagement

/// Toggle the app as a login item via the modern SMAppService API (macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("LaunchAtLogin toggle failed: \(error)")
        }
    }
}
