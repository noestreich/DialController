import IOKit.hid
import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "de.oestreich.DialController", category: "HID")

final class HIDManager: ObservableObject {
    static let shared = HIDManager()

    @Published var isConnected = false
    @Published var isLearning: Bool = false {
        didSet { if !isLearning { pendingLearnId = nil } }
    }
    /// Set when a Dial button is pressed in learn mode; cleared when shortcut is assigned or cancelled.
    @Published var pendingLearnId: String? = nil

    var onButtonPress: ((String) -> Void)?
    var onDial: ((Int) -> Void)? // +1 = CW, -1 = CCW

    private var hidManager: IOHIDManager?
    private var dialDevice: IOHIDDevice?

    /// Modifier usages (page 7, 0xE0–0xE7) that have been PRESSED since the
    /// last button-id emission. We deliberately track "pressed since last
    /// emit" rather than "currently held", because the Ulanzi Dial fires the
    /// entire press-and-release sequence of a single physical button in
    /// roughly 300 microseconds – faster than any reasonable async hop. A
    /// "currently held" set would always be empty by the time we read it.
    /// The set is cleared in the async emit block after the buttonId is built.
    private var burstModifiers: Set<UInt32> = []

    private init() {}

    // Consumer-page usages that represent dial rotation
    private static let dialUsages: Set<UInt32> = [0xE9, 0xEA]
    // Modifier keys – ignored for button identification
    private static let modifierUsages: Set<UInt32> = [0xE0, 0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7]

    // MARK: - Start

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // Match precisely by VendorID + ProductID
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDVendorIDKey as String:  0xFFF1,
            kIOHIDProductIDKey as String: 0x0082
        ] as CFDictionary)

        IOHIDManagerRegisterDeviceMatchingCallback(mgr, onDeviceConnected, selfPtr)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, onDeviceRemoved, selfPtr)

        // Open manager WITHOUT seize – we seize the specific device on connect
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))

        hidManager = mgr
    }

    // MARK: - Device connect / disconnect

    fileprivate func deviceConnected(_ device: IOHIDDevice) {
        let seizeResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        logger.debug("deviceConnected – seize result: \(seizeResult, privacy: .public)")
        if seizeResult != kIOReturnSuccess {
            let fallback = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            logger.debug("fallback open result: \(fallback, privacy: .public)")
        }

        IOHIDDeviceRegisterInputValueCallback(device, onInputValue, selfPtr)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        logger.debug("input callback registered")

        dialDevice = device
        DispatchQueue.main.async { self.isConnected = true }
    }

    fileprivate func deviceRemoved(_ device: IOHIDDevice) {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
        dialDevice = nil
        DispatchQueue.main.async { self.isConnected = false }
    }

    // MARK: - Input events

    fileprivate func handleValue(element: IOHIDElement, value: IOHIDValue) {
        let page     = IOHIDElementGetUsagePage(element)
        let usage    = IOHIDElementGetUsage(element)
        let intValue = IOHIDValueGetIntegerValue(value)

        logger.debug("handleValue page=\(page, privacy: .public) usage=\(String(format: "0x%X", usage), privacy: .public) value=\(intValue, privacy: .public) isLearning=\(self.isLearning, privacy: .public)")

        // Skip shadow / vendor elements
        guard usage != 0xFFFFFFFF else { return }

        // Record modifier PRESSES only. Releases are intentionally ignored –
        // see the comment on `burstModifiers`. The set is cleared in the
        // async emit block, giving "pressed during this HID burst" semantics.
        if page == 7 && HIDManager.modifierUsages.contains(usage) {
            if intValue == 1 {
                burstModifiers.insert(usage)
            }
            return
        }

        // Only care about press events for non-modifier keys
        guard intValue == 1 else { return }

        let isDial = page == 12 && HIDManager.dialUsages.contains(usage)

        // Suppress the device's native keyboard CGEvent NOW, synchronously.
        // The corresponding CGEvent arrives on the session event tap shortly
        // after this IOKit callback returns, so the tap must already be armed.
        // We skip dial rotations (they never send keyboard CGEvents) and the
        // learn phase where suppression is unnecessary because the dial button
        // identity – not the keyboard – is what we're capturing.
        if !isDial && !isLearning {
            EventSuppressor.shared.suppressNext()
        }

        // Wait a short, human-imperceptible window so every IOKit callback
        // of the current HID report burst has settled. The Ulanzi Dial fires
        // the real key event FIRST and only afterwards the modifier events
        // that belong to the same physical press, so reading burstModifiers
        // here guarantees we see the full set.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
            let buttonId: String
            if isDial {
                buttonId = usage == 0xE9 ? "dial:cw" : "dial:ccw"
            } else {
                buttonId = HIDManager.makeButtonId(page: page, usage: usage, modifiers: self.burstModifiers)
            }
            logger.debug("emit buttonId=\(buttonId, privacy: .public) modifiers=\(self.burstModifiers.map { String(format: "0x%X", $0) }.joined(separator: ","), privacy: .public)")

            // Clear the burst set so the next physical press starts fresh.
            // Dial rotations don't clear – modifiers aren't used with rotations
            // anyway and clearing there would swallow modifier state mid-burst
            // if a button+rotate interleaving ever happened.
            if !isDial {
                self.burstModifiers.removeAll()
            }

            if self.isLearning {
                // Phase 1 complete: button identity captured.
                // Stay in learning mode so ConfigView can capture the keyboard shortcut next.
                self.pendingLearnId = buttonId
                return
            }
            if isDial {
                self.onDial?(usage == 0xE9 ? 1 : -1)
            } else {
                self.onButtonPress?(buttonId)
            }
        }
    }

    /// Build a stable, modifier-aware button identifier.
    /// Examples: "7:29", "7:29+E0+E2+E3" (ctrl+alt+cmd held while pressing the same key).
    private static func makeButtonId(page: UInt32, usage: UInt32, modifiers: Set<UInt32>) -> String {
        let base = "\(page):\(usage)"
        guard !modifiers.isEmpty else { return base }
        let suffix = modifiers.sorted().map { String(format: "%X", $0) }.joined(separator: "+")
        return "\(base)+\(suffix)"
    }

    // MARK: - Helpers

    private var selfPtr: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }
}

// MARK: - C callbacks (free functions required by IOKit)

private func onDeviceConnected(
    context: UnsafeMutableRawPointer?,
    result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let ctx = context else { return }
    Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue().deviceConnected(device)
}

private func onDeviceRemoved(
    context: UnsafeMutableRawPointer?,
    result: IOReturn, sender: UnsafeMutableRawPointer?, device: IOHIDDevice
) {
    guard let ctx = context else { return }
    Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue().deviceRemoved(device)
}

private func onInputValue(
    context: UnsafeMutableRawPointer?,
    result: IOReturn, sender: UnsafeMutableRawPointer?, value: IOHIDValue
) {
    guard let ctx = context else { return }
    let element = IOHIDValueGetElement(value)
    Unmanaged<HIDManager>.fromOpaque(ctx).takeUnretainedValue().handleValue(element: element, value: value)
}
