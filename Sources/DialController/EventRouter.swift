import Foundation

final class EventRouter {
    static let shared = EventRouter()

    private init() {
        let hid   = HIDManager.shared
        let store = MappingStore.shared

        // NOTE: suppression of the device's native keyboard CGEvent happens
        // synchronously inside HIDManager.handleValue – the native event
        // arrives on the event tap before this async callback ever runs,
        // so re-arming the tap here would be too late.
        hid.onButtonPress = { id in
            guard let sc = store.shortcut(for: id) else { return }
            KeySender.send(sc)
        }

        hid.onDial = { delta in
            let id = delta > 0 ? "dial:cw" : "dial:ccw"
            guard let sc = store.shortcut(for: id) else { return }
            KeySender.send(sc)
        }
    }
}
