import Foundation

struct DisplayIdentity: Codable, Equatable {
    let uuid: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let name: String

    func sameHardware(as display: DisplayRecord) -> Bool {
        vendor == display.identity.vendor && model == display.identity.model
            && serial == display.identity.serial && !display.builtIn
    }

    func matches(_ display: DisplayRecord) -> Bool {
        let sameUUID = uuid.caseInsensitiveCompare(display.identity.uuid) == .orderedSame
        // Some macOS versions retain EDID metadata for a disabled display but lose its CG UUID.
        // Resolve only a LIVE offline record with the exact hardware signature, never a cached ID.
        let offlineUUIDUnavailable = !display.online && display.identity.uuid.hasPrefix("unavailable-")
            && !uuid.hasPrefix("unavailable-") && (vendor != 0 || model != 0)
        return sameHardware(as: display) && (sameUUID || offlineUUIDUnavailable)
    }
}

struct DisplayRecord: Codable, Equatable {
    let id: UInt32
    let identity: DisplayIdentity
    let builtIn: Bool
    let online: Bool
    let active: Bool
    let main: Bool
    let mirrorOf: UInt32
    let x: Int32
    let y: Int32
    let width: Int
    let height: Int
    let refreshRate: Double

    var isGhost: Bool {
        !online && identity.vendor == 0 && identity.model == 0 && identity.serial == 0
    }
}

struct SavedPlacement: Codable, Equatable {
    let x: Int32
    let y: Int32
    let mirrorSourceUUID: String?
}

struct DisplayPlan {
    let target: DisplayRecord
    let enabled: Bool
    let protectedDisplays: [DisplayRecord]

    static func make(target identity: DisplayIdentity, enabled: Bool, displays: [DisplayRecord]) throws -> DisplayPlan {
        let matches = displays.filter { identity.matches($0) && !$0.isGhost }
        guard matches.count == 1, let target = matches.first else {
            throw SwitchError.message(matches.count > 1
                ? "无法唯一识别投影仪，请在菜单中重新选择。"
                : "暂时找不到已选投影仪。请确认连接线仍接着，或在菜单中重新选择。")
        }
        if target.identity.uuid.hasPrefix("unavailable-") {
            guard displays.filter({ identity.sameHardware(as: $0) && !$0.isGhost }).count == 1 else {
                throw SwitchError.message("有多台外接设备报告了相同身份，无法安全判断哪台是投影仪。请恢复连接后重新选择。")
            }
        }
        let others = displays.filter { $0.id != target.id && $0.online && !$0.isGhost }
        if !enabled && target.online {
            guard others.contains(where: { $0.active }) else {
                throw SwitchError.message("投影仪是当前唯一可用的屏幕。请先启用电脑屏幕或另一台显示器。")
            }
            guard !target.main else {
                throw SwitchError.message("投影仪当前是主显示器。请先在系统设置中将电脑屏幕或另一台显示器设为主显示器。")
            }
            guard !others.contains(where: { $0.mirrorOf == target.id }) else {
                throw SwitchError.message("其他屏幕正在镜像投影仪。请先在系统设置中更换镜像来源。")
            }
        }
        return DisplayPlan(target: target, enabled: enabled, protectedDisplays: others)
    }

    func otherDisplaysPreserved(in displays: [DisplayRecord]) -> Bool {
        protectedDisplays.allSatisfy { original in
            displays.contains { current in
                current.identity.uuid == original.identity.uuid && current.online && current.active == original.active
                    && current.main == original.main && current.x == original.x
                    && current.y == original.y && current.width == original.width
                    && current.height == original.height && current.mirrorOf == original.mirrorOf
                    && abs(current.refreshRate - original.refreshRate) < 0.1
            }
        }
    }
}

enum SwitchError: LocalizedError {
    case message(String)
    case system(String, Int32)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        case .system(let action, let code): return "\(action)失败（\(code)）。可以重新尝试；若仍失败，请重新连接投影仪。"
        }
    }
}
