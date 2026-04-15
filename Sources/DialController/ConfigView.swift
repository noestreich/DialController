import SwiftUI

struct ConfigView: View {
    @EnvironmentObject var store: MappingStore
    @EnvironmentObject var hid: HIDManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.mappings.isEmpty {
                emptyState
            } else {
                mappingList
            }
            Divider()
            footer
        }
        .frame(width: 420)
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Circle()
                .fill(hid.isConnected ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(hid.isConnected ? "Ulanzi Dial verbunden" : "Nicht verbunden")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Dial Controller")
                .font(.headline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var mappingList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach($store.mappings) { $mapping in
                    MappingRow(mapping: $mapping)
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxHeight: 400)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "dial.low")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Noch keine Buttons erkannt.")
                .foregroundStyle(.secondary)
            Text("Klicke 'Button lernen' und drücke einen Button am Dial.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    private var footer: some View {
        HStack {
            Button(hid.isLearning ? "Abbrechen" : "Button lernen") {
                hid.isLearning = !hid.isLearning
            }
            .foregroundColor(hid.isLearning ? .red : .accentColor)

            if hid.isLearning {
                Text("Drücke einen Button…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }

            Spacer()

            Button("Beenden") { NSApp.terminate(nil) }
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut, value: hid.isLearning)
    }
}

// MARK: - MappingRow

struct MappingRow: View {
    @Binding var mapping: ButtonMapping
    @State private var editingLabel = false

    var body: some View {
        HStack(spacing: 12) {
            // Label
            if editingLabel {
                TextField("Label", text: $mapping.label, onCommit: { editingLabel = false })
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
            } else {
                Text(mapping.label)
                    .frame(width: 110, alignment: .leading)
                    .onTapGesture { editingLabel = true }
            }

            Text(mapping.id)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)

            Spacer()

            ShortcutRecorder(shortcut: $mapping.shortcut)

            // Remove button
            Button {
                MappingStore.shared.remove(id: mapping.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
