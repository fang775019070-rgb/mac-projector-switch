import AppKit
import Foundation

func writeJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func runCommand(_ arguments: [String]) throws {
    if arguments.contains("--status") {
        try writeJSON(RuntimeDiagnostics.read())
        return
    }
    if let index = arguments.firstIndex(of: "--set-shortcut") {
        guard index + 1 < arguments.count, let choice = ShortcutChoice(rawValue: arguments[index + 1]) else {
            throw SwitchError.message("请指定有效的快捷键选项。")
        }
        let store = try SettingsStore()
        try store.update { $0.shortcut = choice.rawValue }
        try writeJSON(["shortcut": choice.title])
        return
    }
    let service = try DisplayService()
    if arguments.contains("--diagnose") {
        try writeJSON(service.displays())
        return
    }
    let pathIndex = arguments.firstIndex(of: "--settings")
    let settingsURL = pathIndex.flatMap { index in
        index + 1 < arguments.count ? URL(fileURLWithPath: arguments[index + 1]) : nil
    }
    let store = try SettingsStore(url: settingsURL)
    let controller = ProjectorController(store: store, service: service)
    guard let identity = store.settings.target else { throw SwitchError.message("尚未选择投影仪。") }
    if arguments.contains("--test-cycle") {
        let before = try service.displays()
        guard before.first(where: { identity.matches($0) })?.online == true else {
            throw SwitchError.message("测试要求投影仪初始处于已启用状态。")
        }
        let plan = try DisplayPlan.make(target: identity, enabled: false, displays: before)
        var restored = false
        defer { if !restored { _ = try? controller.setEnabled(true) } }
        _ = try controller.setEnabled(false)
        let disabled = try service.displays()
        try writeJSON(["phase": "disabled", "projector": identity.name,
                       "otherDisplaysPreserved": String(plan.otherDisplaysPreserved(in: disabled))])
        usleep(500_000)
        _ = try controller.setEnabled(true)
        restored = true
        let after = try service.displays()
        let preserved = plan.otherDisplaysPreserved(in: after)
        try writeJSON(["phase": "restored", "projector": identity.name,
                       "otherDisplaysPreserved": String(preserved)])
        guard preserved else { throw SwitchError.message("恢复后其他显示器的布局发生了变化。") }
    } else if arguments.contains("--enable") {
        try writeJSON(controller.setEnabled(true))
    } else if arguments.contains("--disable") {
        try writeJSON(controller.setEnabled(false))
    } else if arguments.contains("--toggle") {
        try writeJSON(controller.toggle())
    } else {
        throw SwitchError.message("支持 --status、--diagnose、--enable、--disable、--toggle 和 --test-cycle。")
    }
}

if CommandLine.arguments.count > 1 {
    do { try runCommand(Array(CommandLine.arguments.dropFirst())) }
    catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(1)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}
