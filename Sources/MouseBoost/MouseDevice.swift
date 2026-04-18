import Foundation
import IOKit
import IOKit.hid

struct MouseDevice {
    let name: String
    let vendorID: Int
    let productID: Int
    let transport: String
    let locationID: Int?

    static func all() -> [MouseDevice] {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            return []
        }

        return devices.compactMap { device in
            let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? "Unknown"
            let vendor = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) ?? 0
            let product = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int) ?? 0
            let transport = (IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String) ?? "Unknown"
            let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int
            return MouseDevice(
                name: name,
                vendorID: vendor,
                productID: product,
                transport: transport,
                locationID: location
            )
        }
        .sorted { $0.name < $1.name }
    }
}
