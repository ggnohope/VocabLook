import SwiftUI

@main
struct VocabLookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("VocabLook", systemImage: "book.closed") {
            Text("VocabLook is running")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
