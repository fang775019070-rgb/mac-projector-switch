import Foundation

final class ProjectorController {
    let store: SettingsStore
    let service: DisplayService
    private(set) var busy = false
    private(set) var disabledByThisRun = false

    init(store: SettingsStore, service: DisplayService) {
        self.store = store
        self.service = service
        if let target = store.settings.target { service.rememberedNames[target.uuid] = target.name }
    }

    func selectedDisplay() throws -> DisplayRecord? {
        guard let identity = store.settings.target else { return nil }
        return try service.displays().first { identity.matches($0) }
    }

    func select(_ display: DisplayRecord) throws {
        guard !display.builtIn, !display.identity.uuid.hasPrefix("unavailable-") else {
            throw SwitchError.message("请选择具有可识别身份的外接投影仪。")
        }
        // Restore the previous projector before changing the binding.
        if disabledByThisRun { _ = try setEnabled(true) }
        try store.update { $0.target = display.identity; $0.placement = nil }
        service.rememberedNames[display.identity.uuid] = display.identity.name
    }

    @discardableResult
    func toggle() throws -> DisplayRecord {
        guard let current = try selectedDisplay() else {
            throw SwitchError.message("尚未找到指定的投影仪。请在“选择投影仪”中选择设备，或确认连接线已接好。")
        }
        return try setEnabled(!current.online)
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> DisplayRecord {
        guard !busy else { throw SwitchError.message("投影仪正在切换，请稍候。") }
        guard let identity = store.settings.target else { throw SwitchError.message("请先在菜单中选择投影仪。") }
        busy = true
        defer { busy = false }
        let displays = try service.displays()
        let plan = try DisplayPlan.make(target: identity, enabled: enabled, displays: displays)
        if !enabled && plan.target.online {
            let placement = service.placement(for: plan.target, in: displays)
            try store.update { $0.placement = placement }
        }
        do {
            let result = try service.change(identity, enabled: enabled, placement: store.settings.placement)
            disabledByThisRun = !enabled
            return result
        } catch {
            if !enabled && plan.target.online {
                disabledByThisRun = (try? selectedDisplay()?.online) != true
            }
            throw error
        }
    }
}
