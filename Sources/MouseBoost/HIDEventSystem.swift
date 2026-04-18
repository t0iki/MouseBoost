import Foundation
import IOKit

// MARK: - Private API bridge (IOHIDEventSystemClient / IOHIDServiceClient)

@_silgen_name("IOHIDEventSystemClientCreate")
private func _IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientCopyServices")
private func _IOHIDEventSystemClientCopyServices(_ client: AnyObject) -> Unmanaged<CFArray>?

@_silgen_name("IOHIDServiceClientCopyProperty")
private func _IOHIDServiceClientCopyProperty(_ service: AnyObject, _ key: CFString) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOHIDServiceClientSetProperty")
@discardableResult
private func _IOHIDServiceClientSetProperty(_ service: AnyObject, _ key: CFString, _ value: CFTypeRef) -> Bool

@_silgen_name("IOHIDServiceClientGetRegistryID")
private func _IOHIDServiceClientGetRegistryID(_ service: AnyObject) -> UInt64

// MARK: - Wrapper

/// サービスは親クライアントが生きている間だけ有効なので、クライアント＋サービス群を一緒に保持する
final class HIDEventSystem {
    private let client: AnyObject

    private init(client: AnyObject) {
        self.client = client
    }

    static func create() -> HIDEventSystem? {
        guard let c = _IOHIDEventSystemClientCreate(kCFAllocatorDefault)?.takeRetainedValue() else {
            return nil
        }
        return HIDEventSystem(client: c)
    }

    func allServices() -> [AnyObject] {
        guard let array = _IOHIDEventSystemClientCopyServices(client)?.takeRetainedValue() as? [AnyObject] else {
            return []
        }
        return array
    }

    func services(vendorID: Int, productID: Int) -> [AnyObject] {
        allServices().filter { service in
            let vid = (Self.getProperty(service, key: "VendorID") as? Int) ?? -1
            let pid = (Self.getProperty(service, key: "ProductID") as? Int) ?? -1
            return vid == vendorID && pid == productID
        }
    }

    static func getProperty(_ service: AnyObject, key: String) -> Any? {
        _IOHIDServiceClientCopyProperty(service, key as CFString)?.takeRetainedValue()
    }

    @discardableResult
    static func setProperty(_ service: AnyObject, key: String, value: CFTypeRef) -> Bool {
        _IOHIDServiceClientSetProperty(service, key as CFString, value)
    }
}

// MARK: - Device resolution (sender ID → VID/PID)

extension HIDEventSystem {
    static func registryID(_ service: AnyObject) -> UInt64 {
        _IOHIDServiceClientGetRegistryID(service)
    }

    /// CGEvent field[87] は IOKit Registry の 64bit Entry ID なので、
    /// IOKit の IOServiceGetMatchingService で該当 io_service_t を引き、VID/PID を取得する
    func resolveSender(senderID: UInt64) -> (vendorID: Int, productID: Int)? {
        let matching = IORegistryEntryIDMatching(senderID)
        // IOServiceGetMatchingService は matching の参照を 1 つ消費する
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        let options = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        let vid = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane,
            "VendorID" as CFString, kCFAllocatorDefault, options
        ) as? Int
        let pid = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane,
            "ProductID" as CFString, kCFAllocatorDefault, options
        ) as? Int
        if let v = vid, let p = pid {
            return (v, p)
        }
        return nil
    }
}
