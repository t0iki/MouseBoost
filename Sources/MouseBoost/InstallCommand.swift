import ArgumentParser
import Foundation
import Darwin

enum LaunchAgent {
    static let label = "com.mouseboost.daemon"

    static var plistURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var logURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/mouseboost.log")
    }

    /// 現在実行中の mouseboost バイナリの絶対パスを解決する（symlink もたどる）
    static func currentExecutablePath() -> String {
        var size: UInt32 = 4096
        var buffer = [CChar](repeating: 0, count: Int(size))
        if _NSGetExecutablePath(&buffer, &size) != 0 {
            buffer = [CChar](repeating: 0, count: Int(size))
            _ = _NSGetExecutablePath(&buffer, &size)
        }
        let raw = String(cString: buffer)
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
    }

    static func makePlist(executable: String) -> [String: Any] {
        [
            "Label": label,
            "ProgramArguments": [executable, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": logURL.path,
            "StandardErrorPath": logURL.path,
            "ProcessType": "Interactive",
        ]
    }

    @discardableResult
    static func runLaunchctl(_ args: [String]) -> (status: Int32, output: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return (-1, "\(error)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}

struct InstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "LaunchAgent に登録して、ログイン時に daemon を自動起動"
    )

    @Option(help: "使用する mouseboost バイナリのパス（デフォルトは現在実行中のバイナリ）")
    var executable: String?

    func run() throws {
        let exePath = executable ?? LaunchAgent.currentExecutablePath()

        guard FileManager.default.isExecutableFile(atPath: exePath) else {
            throw ValidationError("実行可能ファイルが見つかりません: \(exePath)")
        }

        // plist 生成
        let plistDict = LaunchAgent.makePlist(executable: exePath)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plistDict,
            format: .xml,
            options: 0
        )
        let plistURL = LaunchAgent.plistURL
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plistData.write(to: plistURL, options: .atomic)
        print("書き込み: \(plistURL.path)")

        // ログディレクトリも用意
        try FileManager.default.createDirectory(
            at: LaunchAgent.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // すでに読み込まれていたら先に unload（設定変更の反映用）
        _ = LaunchAgent.runLaunchctl(["unload", plistURL.path])

        let load = LaunchAgent.runLaunchctl(["load", "-w", plistURL.path])
        if load.status != 0 {
            print("launchctl load 失敗 (exit=\(load.status)): \(load.output)")
            throw ExitCode(1)
        }

        print("登録完了。次回ログイン時から自動起動します。")
        print("  実行バイナリ: \(exePath)")
        print("  ログ: \(LaunchAgent.logURL.path)")
        print("  今すぐ動作中かの確認: mouseboost status")
        print("  止める: mouseboost uninstall")
    }
}

struct UninstallCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "LaunchAgent の登録を解除して daemon を停止"
    )

    func run() throws {
        let plistURL = LaunchAgent.plistURL
        let unload = LaunchAgent.runLaunchctl(["unload", plistURL.path])
        if unload.status != 0 {
            print("launchctl unload: \(unload.output)")
        }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
            print("削除: \(plistURL.path)")
        }
        print("登録解除完了。")
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "LaunchAgent の状態を表示"
    )

    func run() throws {
        let plistURL = LaunchAgent.plistURL
        print("plist: \(plistURL.path) \(FileManager.default.fileExists(atPath: plistURL.path) ? "(存在)" : "(無し)")")

        let r = LaunchAgent.runLaunchctl(["list", LaunchAgent.label])
        if r.status == 0 {
            print("--- launchctl list ---")
            print(r.output)
        } else {
            print("launchctl list: 登録されていません（exit=\(r.status)）")
        }

        if FileManager.default.fileExists(atPath: LaunchAgent.logURL.path),
           let handle = try? FileHandle(forReadingFrom: LaunchAgent.logURL) {
            // ログ末尾 20 行程度を表示
            let data = handle.readDataToEndOfFile()
            try? handle.close()
            let text = String(data: data, encoding: .utf8) ?? ""
            let tail = text.split(separator: "\n").suffix(20).joined(separator: "\n")
            if !tail.isEmpty {
                print("--- log (tail) ---")
                print(tail)
            }
        }
    }
}
