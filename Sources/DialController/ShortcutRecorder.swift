import SwiftUI

private let kVK_Escape: CGKeyCode = 0x35

/// A view that captures a key combination when clicked.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut?
    @State private var isRecording = false
    @State private var monitor: Any?

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
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            self.capture(event: event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    private func capture(event: NSEvent) {
        if event.keyCode == kVK_Escape {
            stopRecording()
            return
        }

        // Filter to exactly the 4 standard modifier flags
        let flags   = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let cgFlags = flags.cgEventFlags
        // Resolve the key's base character without modifiers (fixes German AltGr combos)
        let char    = baseCharacter(for: event.keyCode)
        let display = flags.displayString + char

        shortcut = KeyShortcut(keyCode: event.keyCode, modifiers: cgFlags.rawValue, display: display)
        stopRecording()
    }

    /// Returns the character that the key at `keyCode` produces without any modifiers.
    /// This correctly handles non-US layouts (e.g. German AltGr keys).
    private func baseCharacter(for keyCode: UInt16) -> String {
        let src = CGEventSource(stateID: .combinedSessionState)
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

// MARK: - Helpers

private extension NSEvent.ModifierFlags {
    var displayString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    var cgEventFlags: CGEventFlags {
        var f = CGEventFlags()
        if contains(.control) { f.insert(.maskControl) }
        if contains(.option)  { f.insert(.maskAlternate) }
        if contains(.shift)   { f.insert(.maskShift) }
        if contains(.command) { f.insert(.maskCommand) }
        return f
    }
}
