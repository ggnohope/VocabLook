import SwiftUI

@main
struct VocabLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            MenuBarContentView().environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Window("Review", id: "review") {
            ReviewView().environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)

        Window("Settings", id: "settings") {
            SettingsView().environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)

        Window("Welcome to VocabLook", id: "onboarding") {
            OnboardingView().environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)
    }
}
