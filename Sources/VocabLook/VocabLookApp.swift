import SwiftUI

@main
struct VocabLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Auxiliary windows (review/settings/onboarding) are managed by WindowManager (AppKit) so
        // they open on the user's current Space; see WindowManager.swift.
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            MenuBarContentView().environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)
    }
}
