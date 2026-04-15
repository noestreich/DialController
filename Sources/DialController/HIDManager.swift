import IOKit.hid
import Combine

final class HIDManager: ObservableObject {
    static let shared = HIDManager()

    @Published var isConnected = false
    @Published var isLearning  = false

    var onButtonPress: ((String) -> Void)?
    var onDial: ((Int) -> Void)? // +1 = CW, -1 = CCW

    private var hidManager: IOHIDManager?
    private var dialDevice: IOHIDDevice?

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
        // Seize THIS device only – exclusive access, OS won't see its key events
        let seizeResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
        if seizeResult != kIOReturnSuccess {
            // Fall back: shared access (original shortcuts will also fire)
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }

        // Register value callback on the specific device
        IOHIDDeviceRegisterInputValueCallback(device, onInputValue, selfPtr)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)

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

        // Only care about press events; skip shadow/vendor elements
        guard intValue == 1, usage != 0xFFFFFFFF else { return }
        // Skip raw modifier keys – they accompany real key events
        if page == 7 && HIDManager.modifierUsages.contains(usage) { return }

        let isDial   = page == 12 && HIDManager.dialUsages.contains(usage)
        let buttonId = isDial
            ? (usage == 0xE9 ? "dial:cw" : "dial:ccw")
            : "\(page):\(usage)"

        DispatchQueue.main.async {
            if self.isLearning {
                let store = MappingStore.shared
                if store.mappings.first(where: { $0.id == buttonId }) == nil {
                    store.upsert(id: buttonId, shortcut: nil)
                }
                self.isLearning = false
                return
            }
            if isDial {
                self.onDial?(usage == 0xE9 ? 1 : -1)
            } else {
                self.onButtonPress?(buttonId)
            }
        }
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
