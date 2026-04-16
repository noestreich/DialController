import SwiftUI
import CoreGraphics
import ApplicationServices
import os.log

private let recLogger = Logger(subsystem: "de.oestreich.DialController", category: "Recorder")

private let kVK_Escape: CGKeyCode = 0x35

/// A view that captures a key combination when clicked.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    var autoStart: Bool = false
    @State private var isRecording = false
    @State private var captureTap: ShortcutCaptureTap?

    var body: some View {
        Button(action: toggleRecording) {
            Text(label)
                .frame(minWidth: 130, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isRecording
                    ? Color.accentColor.opacity(0.15)
                    : Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: 1)
                )
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .onAppear { if autoStart { startRecording() } }
        .onDisappear { stopRecording() }
    }

    private var label: String {
        if isRecording { return "⌨ …" }
        return shortcut?.display ?? "Klicken zum Setzen"
    }

    private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        // Use a CGEventTap at session-headInsert position so we see every
        // keyboard event BEFORE any Carbon hotkey handler (e.g. other apps
        // that registered global hotkeys with RegisterEventHotKey) gets a
        // chance to consume it. NSEvent.addLocalMonitor / addGlobalMonitor
        // can't see events that were already swallowed upstream.
        let tap = ShortcutCaptureTap()
        tap.onCapture = { keyCode, flags in
            self.capture(keyCode: keyCode, flags: flags)
        }
        tap.start()
        captureTap = tap
    }

    private func stopRecording() {
        isRecording = false
        captureTap?.stop()
        captureTap = nil
    }

    private func capture(keyCode: UInt16, flags: CGEventFlags) {
        // Guard against double-capture; stop() invalidates the tap.
        guard isRecording else { return }

        if keyCode == kVK_Escape {
            stopRecording()
            return
        }

        // Filter to the 4 standard modifier masks only.
        var clean = CGEventFlags()
        if flags.contains(.maskCommand)   { clean.insert(.maskCommand) }
        if flags.contains(.maskAlternate) { clean.insert(.maskAlternate) }
        if flags.contains(.maskShift)     { clean.insert(.maskShift) }
        if flags.contains(.maskControl)   { clean.insert(.maskControl) }

        let char    = baseCharacter(for: keyCode)
        let display = displayString(for: clean) + char

        recLogger.debug("capture keyCode=\(keyCode, privacy: .public) flags=\(clean.rawValue, privacy: .public) display=\(display, privacy: .public)")

        shortcut = KeyShortcut(keyCode: keyCode, modifiers: clean.rawValue, display: display)
        stopRecording()
    }

    private func displayString(for flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl)   { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift)     { s += "⇧" }
        if flags.contains(.maskCommand)   { s += "⌘" }
        return s
    }

    /// Returns the character that the key at `keyCode` produces without any modifiers.
    /// Uses `.privateState` so that any modifiers the user is currently holding
    /// down during recording do NOT leak into the Unicode translation –
    /// `.combinedSessionState` would otherwise return e.g. "≈" instead of "X"
    /// when ⌥ is held on a German keyboard layout.
    private func baseCharacter(for keyCode: UInt16) -> String {
        let src = CGEventSource(stateID: .privateState)
        guard let evt = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
        else { return "?" }
        // No modifiers
        evt.flags = []
        var buf = [UniChar](repeating: 0, count: 4)
        var len = 0
        evt.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &len, unicodeString: &buf)
        guard len > 0, let scalar = Unicode.Scalar(buf[0]) else { return "?" }
        return String(scalar).uppercased()
    }
}

// MARK: - CGEventTap wrapper

/// Installs a keyboard CGEventTap that captures the next keyDown and routes
/// it to `onCapture` on the main thread. Events are ALWAYS swallowed while
/// the tap is active so recording a chord cannot accidentally trigger a
/// shortcut in another app.
final class ShortcutCaptureTap {
    var onCapture: ((UInt16, CGEventFlags) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard AXIsProcessTrusted() else {
            recLogger.error("ShortcutCaptureTap: Accessibility NOT trusted – cannot install tap")
            return
        }

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: ShortcutCaptureTap.callback,
            userInfo: selfPtr
        ) else {
            recLogger.error("ShortcutCaptureTap: CGEvent.tapCreate returned nil")
            return
        }

        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = src
        recLogger.debug("ShortcutCaptureTap started")
    }

    func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        if let tap = tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        recLogger.debug("ShortcutCaptureTap stopped")
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passRetained(event) }
        let self_ = Unmanaged<ShortcutCaptureTap>.fromOpaque(refcon).takeUnretainedValue()

        // Re-enable if the system disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = self_.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passRetained(event)
        }

        // Let our own synthetic events pass through (shouldn't hit this tap
        // because they're marked, but be safe).
        if event.getIntegerValueField(.eventSourceUserData) == EventSuppressor.ownEventMark {
            return Unmanaged.passRetained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags   = event.flags

        // The callback runs on the main run loop (we added the source there)
        // so we can dispatch back to main synchronously without reentering.
        DispatchQueue.main.async {
            self_.onCapture?(keyCode, flags)
        }

        // Swallow the event so it can't fire shortcuts in other apps.
        return nil
    }
}
