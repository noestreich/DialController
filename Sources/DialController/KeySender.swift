import CoreGraphics
import Foundation

enum KeySender {
    /// Events posted by us are marked so the EventSuppressor never blocks them.
    private static var ownSource: CGEventSource? = {
        guard let src = CGEventSource(stateID: .privateState) else { return nil }
        src.userData = EventSuppressor.ownEventMark
        return src
    }()

    static func send(_ shortcut: KeyShortcut) {
        let flags   = CGEventFlags(rawValue: shortcut.modifiers)
        let keyCode = CGKeyCode(shortcut.keyCode)

        guard
            let down = CGEvent(keyboardEventSource: ownSource, virtualKey: keyCode, keyDown: true),
            let up   = CGEvent(keyboardEventSource: ownSource, virtualKey: keyCode, keyDown: false)
        else { return }

        down.flags = flags
        up.flags   = flags

        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }
}
