import CoreGraphics
import AppKit

/// Briefly suppresses native keyboard events from the Ulanzi Dial after we fire a remapped shortcut.
/// The tap is kept DISABLED by default and only enabled for ~30ms when actually needed,
/// so it does not interfere with normal IOHIDManager operation or the learn mode.
final class EventSuppressor {
    static let shared = EventSuppressor()

    /// Marker on events we create ourselves – tap will never suppress them.
    static let ownEventMark: Int64 = 0x4469616C // "Dial"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var resetWorkItem: DispatchWorkItem?

    private init() {}

    // MARK: - Setup

    func start() {
        guard AXIsProcessTrusted() else { return }

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue   // keyDown only

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventSuppressor.callback,
            userInfo: selfPtr
        ) else { return }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)

        // Start DISABLED – only enable on demand
        CGEvent.tapEnable(tap: port, enable: false)

        tap = port
        runLoopSource = src
    }

    // MARK: - Public API

    /// Enable the suppressor for the next ~30 ms, then auto-disable.
    func suppressNext() {
        guard let tap else { return }

        // Cancel any pending reset
        resetWorkItem?.cancel()

        CGEvent.tapEnable(tap: tap, enable: true)

        let work = DispatchWorkItem { [weak self] in
            guard let self, let tap = self.tap else { return }
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        resetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.030, execute: work)
    }

    // MARK: - Tap callback

    private static let callback: CGEventTapCallBack = { _, _, event, refcon in
        // Pass our own events through unconditionally
        if event.getIntegerValueField(.eventSourceUserData) == EventSuppressor.ownEventMark {
            return Unmanaged.passRetained(event)
        }
        // Suppress and immediately disable the tap (one-shot)
        if let refcon {
            let self_ = Unmanaged<EventSuppressor>.fromOpaque(refcon).takeUnretainedValue()
            self_.resetWorkItem?.cancel()
            if let tap = self_.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        }
        return nil
    }
}
