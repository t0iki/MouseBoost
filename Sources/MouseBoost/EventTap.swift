import Foundation
import CoreGraphics
import ApplicationServices

/// CGEventTap の callback は C 関数ポインタ。ここから Swift の EventTap に戻る。
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    // タイムアウト/割り込みで tap が無効化されたら再有効化
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reenable()
        return nil
    }

    return tap.process(type: type, event: event)
}

final class EventTap {
    // CGEvent field[87] = IORegistry Entry ID of the sending HID service
    // （実測により判明。kCGMouseEventSenderID の正体）
    private static let mouseEventSenderIDField: CGEventField =
        unsafeBitCast(UInt32(87), to: CGEventField.self)

    /// callback から Unmanaged で参照するため、プロセス終了まで自己保持する
    private static var installed: [EventTap] = []

    private var config: Config
    private let hid: HIDEventSystem
    private var deviceCache: [UInt64: (vid: Int, pid: Int)?] = [:]
    private var fractionalX: [UInt64: Double] = [:]
    private var fractionalY: [UInt64: Double] = [:]
    private var machPort: CFMachPort?
    let verbose: Bool

    init(config: Config, hid: HIDEventSystem, verbose: Bool = false) {
        self.config = config
        self.hid = hid
        self.verbose = verbose
    }

    /// callback と同じ RunLoop (main) で呼ばれる前提で config を差し替える
    func reload(_ newConfig: Config) {
        self.config = newConfig
    }

    /// tap を作成して RunLoop に登録。成功したら self を返す。
    static func install(config: Config, verbose: Bool = false) -> EventTap? {
        guard let hid = HIDEventSystem.create() else { return nil }
        let tap = EventTap(config: config, hid: hid, verbose: verbose)

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let userInfo = Unmanaged.passUnretained(tap).toOpaque()

        guard let port = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            return nil
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap.machPort = port
        installed.append(tap)  // 自己保持してARCで解放されるのを防ぐ
        return tap
    }

    func reenable() {
        if let port = machPort {
            CGEvent.tapEnable(tap: port, enable: true)
        }
    }

    func dumpEvent(_ event: CGEvent) {
        // 既知 + 怪しい field を列挙して非0のものだけ出す
        let candidates: [Int] = Array(40...100)
        var parts: [String] = []
        for c in candidates {
            let field = unsafeBitCast(UInt32(c), to: CGEventField.self)
            let v = event.getIntegerValueField(field)
            if v != 0 { parts.append("[\(c)]=\(v)") }
        }
        let line = "event fields: \(parts.joined(separator: " "))\n"
        FileHandle.standardError.write(Data(line.utf8))
    }

    func process(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let senderID = UInt64(bitPattern: event.getIntegerValueField(Self.mouseEventSenderIDField))

        // デバイス解決（cache）
        let device: (vid: Int, pid: Int)?
        if let cached = deviceCache[senderID] {
            device = cached
        } else {
            if let resolved = hid.resolveSender(senderID: senderID) {
                device = (resolved.vendorID, resolved.productID)
            } else {
                device = nil
            }
            deviceCache[senderID] = device
        }

        guard let dev = device,
              let deviceCfg = config.find(vendorID: dev.vid, productID: dev.pid)
        else {
            if verbose {
                let vp = device.map { String(format: "0x%04X:0x%04X", $0.vid, $0.pid) } ?? "unknown"
                FileHandle.standardError.write(Data("skip sender=\(senderID) device=\(vp)\n".utf8))
            }
            return Unmanaged.passUnretained(event)
        }

        let speed = deviceCfg.speed
        let rawDX = event.getIntegerValueField(.mouseEventDeltaX)
        let rawDY = event.getIntegerValueField(.mouseEventDeltaY)

        // Magic Mouse 等のマルチタッチ系はネイティブの移動が飲み込み不可なので、
        // 「上乗せ分」だけ warp する: extra = raw * (speed - 1)
        // 結果、総移動量 = raw(ネイティブ) + raw*(speed-1)(warp) = raw * speed
        guard let ref = CGEvent(source: nil) else {
            return Unmanaged.passUnretained(event)
        }
        let cur = ref.location

        let carryX = fractionalX[senderID] ?? 0
        let carryY = fractionalY[senderID] ?? 0
        let extraX = Double(rawDX) * (speed - 1.0) + carryX
        let extraY = Double(rawDY) * (speed - 1.0) + carryY
        let moveX = extraX.rounded(.towardZero)
        let moveY = extraY.rounded(.towardZero)
        fractionalX[senderID] = extraX - moveX
        fractionalY[senderID] = extraY - moveY

        if moveX != 0 || moveY != 0 {
            let newLoc = CGPoint(x: cur.x + moveX, y: cur.y + moveY)
            CGWarpMouseCursorPosition(newLoc)

            if verbose {
                let vp = String(format: "0x%04X:0x%04X", dev.vid, dev.pid)
                let line = "warp \(vp) d=(\(rawDX),\(rawDY)) extra=(\(Int(moveX)),\(Int(moveY))) cur=(\(Int(cur.x)),\(Int(cur.y)))→(\(Int(newLoc.x)),\(Int(newLoc.y))) x\(speed)\n"
                FileHandle.standardError.write(Data(line.utf8))
            }
        }

        return Unmanaged.passUnretained(event)
    }
}

enum Accessibility {
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: CFDictionary = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
