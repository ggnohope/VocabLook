import AppKit
import CoreGraphics

/// Observes Ctrl+Cmd+D system-wide via a session-level CGEventTap (listen-only, so it does NOT
/// consume the event — the native Look Up still opens). A passive NSEvent global monitor cannot
/// see Ctrl+Cmd+D because macOS consumes that combo for the Look Up service before delivering it;
/// a head-inserted session event tap sits early enough in the pipeline to observe it.
final class HotkeyMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let keyCodeD: Int64 = 0x02 // ANSI 'D'

    /// Called on the main thread when Ctrl+Cmd+D is pressed.
    var onLookup: (() -> Void)?

    func start() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                if let refcon {
                    Unmanaged<HotkeyMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                        .handleTap(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            AppLog.log("CGEvent.tapCreate FAILED (Input Monitoring not granted?)")
            return
        }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleTap(type: CGEventType, event: CGEvent) {
        // The OS can disable a tap after a timeout or heavy input; re-enable it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .keyDown else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)

        guard hasCommand, hasControl, keyCode == keyCodeD else { return }
        DispatchQueue.main.async { [weak self] in self?.onLookup?() }
    }
}
