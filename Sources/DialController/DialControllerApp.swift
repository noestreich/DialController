import SwiftUI

@main
struct DialControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Pure menu bar app – no regular window
        MenuBarExtra {
            ConfigView()
                .environmentObject(MappingStore.shared)
                .environmentObject(HIDManager.shared)
        } label: {
            Label("Dial", systemImage: "dial.low.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
