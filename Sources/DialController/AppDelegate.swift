import Cocoa
import SwiftUI
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Prompt for Accessibility (needed for CGEventPost)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)

        // Start listening for the Ulanzi Dial and wire up event routing
        HIDManager.shared.start()
        _ = EventRouter.shared

        // Install the keyboard event tap used to swallow the device's native
        // CGEvents (e.g. the factory-mapped Cmd+V) right before we fire our
        // own remapped shortcut. The tap starts disabled and is only armed
        // briefly around each dial button press.
        EventSuppressor.shared.start()

        // ── Status bar item ──────────────────────────────────────────────
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "dial.low.fill",
                                   accessibilityDescription: "Dial Controller")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        // ── Popover ──────────────────────────────────────────────────────
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 320)
        popover.behavior = .transient     // closes when clicking outside
        popover.animates = true

        let rootView = ConfigView()
            .environmentObject(MappingStore.shared)
            .environmentObject(HIDManager.shared)
        popover.contentViewController = NSHostingController(rootView: rootView)
    }

    // MARK: - Toggle

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Make the popover window key so keyboard events (ShortcutRecorder) work
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
