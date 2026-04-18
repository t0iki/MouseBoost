import ArgumentParser

@main
struct MouseBoost: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mouseboost",
        abstract: "macOS でマウスごとにポインター速度を設定する CLI",
        subcommands: [
            ListCommand.self,
            SetCommand.self,
            RemoveCommand.self,
            ShowCommand.self,
            DaemonCommand.self,
            InstallCommand.self,
            UninstallCommand.self,
            StatusCommand.self,
            InspectCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
