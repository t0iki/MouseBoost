import ArgumentParser
import Foundation
import CoreFoundation
import Darwin

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        abstract: "フォアグラウンド常駐。マウス移動を傍受して per-device に速度を適用"
    )

    @Flag(help: "アクセシビリティ権限のダイアログを出して終了")
    var requestPermission: Bool = false

    @Flag(name: .shortAndLong, help: "デバッグログを出力")
    var verbose: Bool = false

    func run() throws {
        setbuf(stdout, nil)  // 常駐時は逐次flushしたい
        if requestPermission {
            _ = Accessibility.isTrusted(prompt: true)
            print("システム設定 → プライバシーとセキュリティ → アクセシビリティ で mouseboost を許可してください。")
            return
        }

        let cfg = Config.load()
        if cfg.devices.isEmpty {
            print("設定されたデバイスがありません。`mouseboost set` で設定してから再実行してください。")
            throw ExitCode(1)
        }

        if !Accessibility.isTrusted() {
            print("アクセシビリティ権限がありません。")
            print("  1. `mouseboost daemon --request-permission` を実行してダイアログを出す")
            print("  2. システム設定 → プライバシーとセキュリティ → アクセシビリティ で mouseboost を許可")
            print("  3. もう一度 `mouseboost daemon` を実行")
            throw ExitCode(1)
        }

        // NOTE: tap は callback から Unmanaged で参照されるので、ここで強参照を保持する
        guard let tap = EventTap.install(config: cfg, verbose: verbose) else {
            print("CGEventTap の作成に失敗しました。アクセシビリティ権限の再確認を。")
            throw ExitCode(1)
        }

        print("mouseboost daemon 起動（Ctrl+C で停止）")
        logApplied(cfg)

        // config.json を 1 秒おきに mtime チェックして差分があれば再ロード
        startConfigWatcher(tap: tap)

        signal(SIGINT) { _ in
            Darwin.exit(0)
        }

        CFRunLoopRun()
    }

    private func logApplied(_ cfg: Config) {
        for d in cfg.devices {
            let vp = String(format: "0x%04X:0x%04X", d.vendorID, d.productID)
            print("  適用中: \(d.name ?? "unknown") \(vp) speed=\(d.speed)x")
        }
    }

    private func startConfigWatcher(tap: EventTap) {
        let path = Config.defaultPath.path
        var lastMtime = mtime(of: path)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler {
            let now = mtime(of: path)
            guard now != lastMtime else { return }
            lastMtime = now
            let newCfg = Config.load()
            tap.reload(newCfg)
            print("設定を再読込: \(newCfg.devices.count) デバイス")
            self.logApplied(newCfg)
        }
        timer.resume()
        // timer は強参照しないと消えるので main runloop に紐付けるためここで保持
        Self.configTimer = timer
    }

    private static var configTimer: DispatchSourceTimer?
}

private func mtime(of path: String) -> Date? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path) else {
        return nil
    }
    return attrs[.modificationDate] as? Date
}
