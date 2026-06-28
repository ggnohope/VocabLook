import AppKit

/// Glues the hotkey monitor to capture → definition → store → HUD. Notifies AppState on success.
final class CaptureCoordinator {
    private let monitor = HotkeyMonitor()
    private let capturer = LookupCapturer()
    private let hud = HUDController()
    private let store: Store
    private let appState: AppState

    init(store: Store = .shared, appState: AppState) {
        self.store = store
        self.appState = appState
    }

    func start() {
        monitor.onLookup = { [weak self] in self?.handleLookup() }
        monitor.start()
    }

    func stop() { monitor.stop() }

    private func handleLookup() {
        // Give the OS a beat to finalize the selection the user is looking up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self else { return }
            guard let captured = self.capturer.capture() else {
                self.hud.show(term: "", subtitle: "Couldn't read the selection", onUndo: {})
                return
            }
            let def = DefinitionService.define(captured.term)
            do {
                let entry = try self.store.saveLookup(
                    term: captured.term, definition: def.definition,
                    partOfSpeech: def.partOfSpeech, ipa: def.ipa, context: captured.context,
                    sourceApp: captured.sourceApp, sourceDetail: captured.sourceDetail, now: Date())
                self.appState.refresh()
                self.hud.show(term: entry.term, subtitle: "Card created · first review tomorrow") { [weak self] in
                    try? self?.store.deleteEntry(id: entry.id)
                    self?.appState.refresh()
                }
            } catch {
                self.hud.show(term: captured.term, subtitle: "Couldn't save", onUndo: {})
            }
        }
    }
}
