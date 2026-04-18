import ArgumentParser
import Foundation

func parseID(_ s: String) -> Int? {
    if s.lowercased().hasPrefix("0x") {
        return Int(s.dropFirst(2), radix: 16)
    }
    return Int(s)
}

// MARK: - list

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "接続中のマウスを一覧表示"
    )

    func run() throws {
        let devices = MouseDevice.all()
        if devices.isEmpty {
            print("マウスが見つかりませんでした。")
            return
        }

        func pad(_ s: String, _ n: Int) -> String {
            let t = String(s.prefix(n))
            return t.padding(toLength: n, withPad: " ", startingAt: 0)
        }

        let cfg = Config.load()

        let header = "\(pad("NAME", 36)) \(pad("VENDOR", 8)) \(pad("PRODUCT", 9)) \(pad("TRANSPORT", 10)) \(pad("CONFIG", 8))"
        print(header)
        print(String(repeating: "-", count: header.count))
        for d in devices {
            let vid = String(format: "0x%04X", d.vendorID)
            let pid = String(format: "0x%04X", d.productID)
            let configured = cfg.find(vendorID: d.vendorID, productID: d.productID)
                .map { String(format: "%.2fx", $0.speed) } ?? "-"
            print("\(pad(d.name, 36)) \(pad(vid, 8)) \(pad(pid, 9)) \(pad(d.transport, 10)) \(pad(configured, 8))")
        }
    }
}

// MARK: - set

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "指定マウスのポインター速度倍率を設定に保存"
    )

    @Option(name: [.customLong("vendor-id"), .short], help: "Vendor ID（例: 0x004C または 76）")
    var vendorID: String

    @Option(name: [.customLong("product-id"), .short], help: "Product ID（例: 0x0269 または 617）")
    var productID: String

    @Option(name: .shortAndLong, help: "速度倍率。1.0 が等倍、0.5 で半分、2.0 で倍。")
    var speed: Double

    func run() throws {
        guard let vid = parseID(vendorID) else {
            throw ValidationError("vendor-id の形式が不正: \(vendorID)")
        }
        guard let pid = parseID(productID) else {
            throw ValidationError("product-id の形式が不正: \(productID)")
        }

        // 接続中デバイスから名前を拾えれば入れておく
        let name = MouseDevice.all().first { $0.vendorID == vid && $0.productID == pid }?.name

        var cfg = Config.load()
        cfg.upsert(DeviceConfig(vendorID: vid, productID: pid, name: name, speed: speed))
        try cfg.save()
        let nameStr = name.map { " (\($0))" } ?? ""
        print("保存しました: vendor=0x\(String(vid, radix: 16)) product=0x\(String(pid, radix: 16))\(nameStr) speed=\(speed)x")
        print("適用するには `mouseboost daemon` を起動してください。")
    }
}

// MARK: - remove

struct RemoveCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "指定マウスの設定を削除"
    )

    @Option(name: [.customLong("vendor-id"), .short])
    var vendorID: String

    @Option(name: [.customLong("product-id"), .short])
    var productID: String

    func run() throws {
        guard let vid = parseID(vendorID), let pid = parseID(productID) else {
            throw ValidationError("ID 解析失敗")
        }
        var cfg = Config.load()
        if cfg.remove(vendorID: vid, productID: pid) {
            try cfg.save()
            print("削除しました。")
        } else {
            print("該当する設定はありませんでした。")
        }
    }
}

// MARK: - show

struct ShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "現在の設定を表示"
    )

    func run() throws {
        let cfg = Config.load()
        if cfg.devices.isEmpty {
            print("設定されているデバイスはありません。")
            return
        }
        print("設定ファイル: \(Config.defaultPath.path)")
        for d in cfg.devices {
            let vid = String(format: "0x%04X", d.vendorID)
            let pid = String(format: "0x%04X", d.productID)
            let name = d.name ?? "(unknown)"
            print("  \(name)  vendor=\(vid) product=\(pid) speed=\(d.speed)x")
        }
    }
}

// MARK: - inspect (debug)

struct InspectCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "HIDサービスプロパティをダンプ（デバッグ用）",
        shouldDisplay: false
    )

    @Option(name: [.customLong("vendor-id"), .short])
    var vendorID: String?

    @Option(name: [.customLong("product-id"), .short])
    var productID: String?

    func run() throws {
        guard let hid = HIDEventSystem.create() else {
            throw ValidationError("HIDEventSystem 作成失敗")
        }
        let all = hid.allServices()
        let services: [AnyObject]
        if let vs = vendorID, let ps = productID,
           let vid = parseID(vs), let pid = parseID(ps) {
            services = all.filter {
                let v = HIDEventSystem.getProperty($0, key: "VendorID") as? Int
                let p = HIDEventSystem.getProperty($0, key: "ProductID") as? Int
                return v == vid && p == pid
            }
        } else {
            services = all
        }

        print("matched services: \(services.count)")
        let keys = [
            "Product", "VendorID", "ProductID", "PrimaryUsage", "PrimaryUsagePage",
            "Transport", "LocationID", "SerialNumber",
        ]
        for (i, svc) in services.enumerated() {
            print("--- service[\(i)] ---")
            let regID = HIDEventSystem.registryID(svc)
            print("  registryID(IOHIDServiceClientGetRegistryID) = \(regID)")
            for k in keys {
                let v = HIDEventSystem.getProperty(svc, key: k)
                print("  \(k) = \(v.map { "\($0)" } ?? "nil")")
            }
        }
    }
}
