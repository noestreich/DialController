import Foundation
import CoreGraphics

// MARK: - Data models

struct KeyShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt64   // CGEventFlags.rawValue
    let display: String     // Human-readable, e.g. "⌘⇧K"
}

struct ButtonMapping: Codable, Identifiable, Equatable {
    /// Stable ID: "usagePage:usage"  or  "dial:cw" / "dial:ccw"
    var id: String
    var label: String
    var shortcut: KeyShortcut?
}

// MARK: - Store

final class MappingStore: ObservableObject {
    static let shared = MappingStore()

    @Published var mappings: [ButtonMapping] = [] {
        didSet { persist() }
    }

    private let defaultsKey = "com.dial.mappings"

    private init() { load() }

    // MARK: Accessors

    func shortcut(for id: String) -> KeyShortcut? {
        mappings.first { $0.id == id }?.shortcut
    }

    func upsert(id: String, label: String? = nil, shortcut: KeyShortcut?) {
        if let idx = mappings.firstIndex(where: { $0.id == id }) {
            if let label { mappings[idx].label = label }
            mappings[idx].shortcut = shortcut
        } else {
            mappings.append(ButtonMapping(
                id: id,
                label: label ?? defaultLabel(for: id),
                shortcut: shortcut
            ))
        }
    }

    func remove(id: String) {
        mappings.removeAll { $0.id == id }
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: defaultsKey),
            let decoded = try? JSONDecoder().decode([ButtonMapping].self, from: data)
        else { return }
        mappings = decoded
    }

    // MARK: Helpers

    private func defaultLabel(for id: String) -> String {
        switch id {
        case "dial:cw":  return "Dial +"
        case "dial:ccw": return "Dial -"
        default:         return "Button (\(id))"
        }
    }
}
