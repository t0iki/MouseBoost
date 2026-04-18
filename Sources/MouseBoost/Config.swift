import Foundation

struct DeviceConfig: Codable, Equatable {
    var vendorID: Int
    var productID: Int
    var name: String?
    /// マウス移動量に掛ける倍率（1.0 = 等倍）
    var speed: Double

    enum CodingKeys: String, CodingKey {
        case vendorID = "vendor_id"
        case productID = "product_id"
        case name
        case speed
    }
}

struct Config: Codable {
    var devices: [DeviceConfig]

    init(devices: [DeviceConfig] = []) {
        self.devices = devices
    }

    static var defaultPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/mouseboost/config.json")
    }

    static func load(from url: URL = Config.defaultPath) -> Config {
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(Config.self, from: data)
        else {
            return Config()
        }
        return cfg
    }

    func save(to url: URL = Config.defaultPath) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: url, options: .atomic)
    }

    func find(vendorID: Int, productID: Int) -> DeviceConfig? {
        devices.first { $0.vendorID == vendorID && $0.productID == productID }
    }

    mutating func upsert(_ device: DeviceConfig) {
        if let i = devices.firstIndex(where: { $0.vendorID == device.vendorID && $0.productID == device.productID }) {
            devices[i] = device
        } else {
            devices.append(device)
        }
    }

    @discardableResult
    mutating func remove(vendorID: Int, productID: Int) -> Bool {
        let before = devices.count
        devices.removeAll { $0.vendorID == vendorID && $0.productID == productID }
        return devices.count != before
    }
}
