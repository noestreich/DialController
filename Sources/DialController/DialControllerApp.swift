import SwiftUI

@main
struct DialControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // All UI is driven by AppDelegate via NSStatusItem + NSPopover.
        // This empty Settings scene satisfies the Swift compiler requirement
        // for at least one scene in @main App structs.
        Settings { EmptyView() }
    }
}
