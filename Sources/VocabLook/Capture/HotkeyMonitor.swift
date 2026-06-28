import AppKit

/// Observes Ctrl+Cmd+D system-wide WITHOUT consuming it, so the native Look Up still opens.
final class HotkeyMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let keyCodeD: UInt16 = 0x02 // ANSI 'D'

    /// Called on the main thread when Ctrl+Cmd+D is pressed.
    var onLookup: (() -> Void)?

    func start() {
        // Global monitor: fires when another app is frontmost (the common case).
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        // Local monitor: fires when one of our own windows is focused. Returns the event so it isn't swallowed.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let g = globalMonitor { NSEvent.removeMonitor(g); globalMonitor = nil }
        if let l = localMonitor { NSEvent.removeMonitor(l); localMonitor = nil }
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.control, .command], event.keyCode == keyCodeD else { return }
        DispatchQueue.main.async { [weak self] in self?.onLookup?() }
    }
}
