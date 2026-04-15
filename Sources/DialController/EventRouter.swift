import Foundation

final class EventRouter {
    static let shared = EventRouter()

    private init() {
        let hid   = HIDManager.shared
        let store = MappingStore.shared

        hid.onButtonPress = { id in
            guard let sc = store.shortcut(for: id) else { return }
            // Suppress the device's native keyboard event before firing our shortcut
            EventSuppressor.shared.suppressNext()
            KeySender.send(sc)
        }

        hid.onDial = { delta in
            let id = delta > 0 ? "dial:cw" : "dial:ccw"
            guard let sc = store.shortcut(for: id) else { return }
            EventSuppressor.shared.suppressNext()
            KeySender.send(sc)
        }
    }
}
