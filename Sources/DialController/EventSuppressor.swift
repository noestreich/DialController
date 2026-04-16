import CoreGraphics
import AppKit
import QuartzCore
import os.log

private let logger = Logger(subsystem: "de.oestreich.DialController", category: "Suppressor")

/// Swallows keyboard CGEvents produced by the Ulanzi Dial in a short window
/// around each dial button press, so that the device's factory-mapped shortcut
/// (e.g. Cmd+V) does NOT fire alongside our remapped shortcut.
///
/// Design notes:
/// - The tap is installed at `.cgSessionEventTap` / `.headInsertEventTap`
///   which sees every keyboard event in the session before any Carbon hotkey
///   handler or foreground application receives it.
/// - The tap is **always enabled** once started. Earlier "one-shot" designs
///   that toggled enable/disable around each press lost events whenever the
///   system synthesised the CGEvent before our IOKit callback fired.
/// - `suppressNext()` simply pushes `suppressUntil` forward by ~100 ms. The
///   tap callback drops any non-owned keyboard event whose timestamp falls
///   inside the window.
/// - Events we post ourselves carry `eventSourceUserData == ownEventMark` and
///   pass through unconditionally.
final class EventSuppressor {
    static let shared = EventSuppressor()

    /// Marker on events we create ourselves – tap will never suppress them.
    static let ownEventMark: Int64 = 0x4469616C // "Dial"

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Mach absolute time (seconds, `CACurrentMediaTime()`) until which
    /// all non-owned keyboard events are dropped.
    private var suppressUntil: CFTimeInterval = 0

    private init() {}

    // MARK: - Setup

    func start() {
        guard AXIsProcessTrusted() else {
            logger.error("start(): Accessibility NOT trusted – event tap NOT installed. User must grant permission in System Settings › Privacy & Security › Accessibility.")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: EventSuppressor.callback,
            userInfo: selfPtr
        ) else {
            logger.error("start(): CGEvent.tapCreate returned nil")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = src
        logger.debug("start(): tap installed, always-enabled mode")
    }

    // MARK: - Public API

    /// Open a suppression window (~100 ms) during which non-owned keyboard
    /// events are dropped. Called synchronously from `HIDManager.handleValue`
    /// the moment a dial button press is detected.
    func suppressNext() {
        let until = CACurrentMediaTime() + 0.100
        suppressUntil = until
        logger.debug("suppressNext(): window until \(until, privacy: .public)")
    }

    // MARK: - Tap callback

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passRetained(event) }
        let self_ = Unmanaged<EventSuppressor>.fromOpaque(refcon).takeUnretainedValue()

        // The system disables a tap that takes too long or after wake. Re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            logger.error("tap disabled by system (type=\(type.rawValue, privacy: .public)) – re-enabling")
            if let tap = self_.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Never touch events we posted ourselves.
        if event.getIntegerValueField(.eventSourceUserData) == EventSuppressor.ownEventMark {
            return Unmanaged.passRetained(event)
        }

        // Drop the event if we're inside the suppression window.
        if CACurrentMediaTime() < self_.suppressUntil {
            logger.debug("suppressing event type=\(type.rawValue, privacy: .public)")
            return nil
        }

        return Unmanaged.passRetained(event)
    }
}
