import AppKit
import CoreGraphics
import Darwin
import Foundation

final class DisplayService {
    private typealias GetList = @convention(c)
        (UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> CGError
    private typealias SetEnabled = @convention(c)
        (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private let handles: [UnsafeMutableRawPointer]
    private let getList: GetList
    private let setEnabled: SetEnabled
    var rememberedNames: [String: String] = [:]

    init() throws {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
        ]
        let loadedHandles = paths.compactMap { dlopen($0, RTLD_LAZY | RTLD_LOCAL) }
        handles = loadedHandles
        func symbol(_ names: [String]) -> UnsafeMutableRawPointer? {
            for name in names {
                for handle in loadedHandles {
                    if let pointer = dlsym(handle, name) { return pointer }
                }
            }
            return nil
        }
        guard let list = symbol(["CGSGetDisplayList", "SLSGetDisplayList"]),
              let enabled = symbol(["CGSConfigureDisplayEnabled", "SLSConfigureDisplayEnabled"]) else {
            throw SwitchError.message("当前系统不支持此显示切换方式。macOS 更新后可能需要更新小工具。")
        }
        getList = unsafeBitCast(list, to: GetList.self)
        setEnabled = unsafeBitCast(enabled, to: SetEnabled.self)
    }

    func displays() throws -> [DisplayRecord] {
        var capacity = 16
        var ids: [UInt32] = []
        while capacity <= 512 {
            var buffer = [UInt32](repeating: 0, count: capacity)
            var count: UInt32 = 0
            let error = getList(UInt32(capacity), &buffer, &count)
            guard error == .success else { throw SwitchError.system("读取显示器", error.rawValue) }
            guard count <= capacity else { throw SwitchError.message("系统返回的显示器列表异常，请稍后重试。") }
            if count < capacity {
                ids = Array(buffer.prefix(Int(count)))
                break
            }
            capacity *= 2
        }
        guard !ids.isEmpty else { throw SwitchError.message("未能读取当前显示器。请在已登录的桌面会话中运行小工具。") }
        var names: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                names[id.uint32Value] = screen.localizedName
            }
        }
        return ids.map { id in
            let uuid = CGDisplayCreateUUIDFromDisplayID(id).map {
                CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
            } ?? "unavailable-\(id)"
            let builtIn = CGDisplayIsBuiltin(id) != 0
            let name = names[id] ?? rememberedNames[uuid] ?? (builtIn ? "电脑内置屏幕" : "外接显示器 \(id)")
            rememberedNames[uuid] = name
            let identity = DisplayIdentity(uuid: uuid, vendor: CGDisplayVendorNumber(id),
                                           model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id), name: name)
            let bounds = CGDisplayBounds(id)
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayRecord(id: id, identity: identity, builtIn: builtIn,
                online: CGDisplayIsOnline(id) != 0, active: CGDisplayIsActive(id) != 0,
                main: CGDisplayIsMain(id) != 0, mirrorOf: CGDisplayMirrorsDisplay(id),
                x: Int32(clamping: Int(bounds.origin.x)), y: Int32(clamping: Int(bounds.origin.y)),
                width: mode?.width ?? 0, height: mode?.height ?? 0, refreshRate: mode?.refreshRate ?? 0)
        }.filter { !$0.isGhost }
    }

    func placement(for target: DisplayRecord, in displays: [DisplayRecord]) -> SavedPlacement {
        SavedPlacement(x: target.x, y: target.y,
                       mirrorSourceUUID: displays.first { $0.id == target.mirrorOf }?.identity.uuid)
    }

    @discardableResult
    func change(_ identity: DisplayIdentity, enabled: Bool, placement: SavedPlacement?) throws -> DisplayRecord {
        // Numeric display IDs can change after sleep or reconnection. Always resolve live identity.
        let before = try displays()
        let plan = try DisplayPlan.make(target: identity, enabled: enabled, displays: before)
        if plan.target.online == enabled { return plan.target }

        if enabled, let uuid = placement?.mirrorSourceUUID,
           !before.contains(where: { $0.identity.uuid == uuid && $0.online && $0.id != plan.target.id }) {
            throw SwitchError.message("投影仪原来的镜像来源暂时不可用。请先启用该屏幕，再恢复投影仪。")
        }
        do {
            try applyConnection(plan.target, enabled: enabled)
            try waitFor(identity, enabled: enabled)
            // The compositor's automatic layout happens after the enable transaction. A separate
            // transaction is required both to retain other origins and to position a re-enabled target.
            try restoreLayout(target: enabled ? identity : nil, placement: placement,
                              protectedDisplays: plan.protectedDisplays)
            var after = try displays()
            for _ in 0..<8 where !plan.otherDisplaysPreserved(in: after) {
                usleep(100_000)
                after = try displays()
            }
            guard plan.otherDisplaysPreserved(in: after) else {
                throw SwitchError.message("切换时系统调整了其他屏幕的布局。")
            }
            let resolved = after.first { identity.matches($0) }
            guard enabled ? resolved?.online == true : resolved?.online != true else {
                throw SwitchError.message("投影仪没有保持切换后的状态。")
            }
            // Keep a meaningful name and UUID even when CoreGraphics hides an offline UUID.
            return DisplayRecord(id: resolved?.id ?? plan.target.id, identity: identity,
                builtIn: false, online: enabled, active: resolved?.active ?? false,
                main: resolved?.main ?? false, mirrorOf: resolved?.mirrorOf ?? 0,
                x: resolved?.x ?? plan.target.x, y: resolved?.y ?? plan.target.y,
                width: resolved?.width ?? 0, height: resolved?.height ?? 0, refreshRate: resolved?.refreshRate ?? 0)
        } catch {
            let rollback = recover(plan, originalDisplays: before)
            throw SwitchError.message(error.localizedDescription + (rollback
                ? "\n已恢复切换前的状态。"
                : "\n请在菜单中选择“恢复投影仪”，或重新连接投影仪。"))
        }
    }

    private func applyConnection(_ target: DisplayRecord, enabled: Bool) throws {
        var reference: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&reference)
        guard begin == .success, let configuration = reference else {
            throw SwitchError.system("开始显示切换", begin.rawValue)
        }
        var finished = false
        defer { if !finished { CGCancelDisplayConfiguration(configuration) } }
        if !enabled && target.mirrorOf != 0 {
            try check(CGConfigureDisplayMirrorOfDisplay(configuration, target.id, kCGNullDirectDisplay), "调整投影仪镜像")
        }
        try check(setEnabled(configuration, target.id, enabled), enabled ? "启用投影仪" : "停用投影仪")
        let complete = CGCompleteDisplayConfiguration(configuration, .forSession)
        finished = true
        try check(complete, "完成显示切换")
    }

    private func waitFor(_ identity: DisplayIdentity, enabled: Bool) throws {
        for _ in 0..<15 {
            let target = try displays().first { identity.matches($0) }
            if enabled ? target?.online == true : target?.online != true {
                usleep(120_000)
                return
            }
            usleep(100_000)
        }
        throw SwitchError.message("投影仪没有完成切换，请稍后重试。")
    }

    private func restoreLayout(target identity: DisplayIdentity?, placement: SavedPlacement?,
                               protectedDisplays: [DisplayRecord]) throws {
        let live = try displays()
        var reference: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&reference)
        guard begin == .success, let configuration = reference else {
            throw SwitchError.system("保留屏幕排列", begin.rawValue)
        }
        var finished = false
        defer { if !finished { CGCancelDisplayConfiguration(configuration) } }
        for original in protectedDisplays where original.mirrorOf == 0 {
            guard let current = live.first(where: { $0.identity.uuid == original.identity.uuid && $0.online }) else {
                throw SwitchError.message("另一块屏幕的连接状态在切换过程中发生了变化。")
            }
            try check(CGConfigureDisplayOrigin(configuration, current.id, original.x, original.y), "保留其他屏幕的位置")
        }
        if let identity, let placement {
            let matches = live.filter { identity.matches($0) && $0.online }
            guard matches.count == 1, let target = matches.first else {
                throw SwitchError.message("无法恢复投影仪的位置，请重新连接投影仪。")
            }
            if let uuid = placement.mirrorSourceUUID {
                guard let source = live.first(where: { $0.identity.uuid == uuid && $0.online }) else {
                    throw SwitchError.message("投影仪原来的镜像来源已断开。")
                }
                try check(CGConfigureDisplayMirrorOfDisplay(configuration, target.id, source.id), "恢复投影仪镜像")
            } else {
                try check(CGConfigureDisplayOrigin(configuration, target.id, placement.x, placement.y), "恢复投影仪位置")
            }
        }
        let complete = CGCompleteDisplayConfiguration(configuration, .forSession)
        finished = true
        try check(complete, "保留屏幕排列")
    }

    private func recover(_ plan: DisplayPlan, originalDisplays: [DisplayRecord]) -> Bool {
        do {
            let current = try displays()
            guard let target = current.first(where: { plan.target.identity.matches($0) }) else { return false }
            let saved = placement(for: plan.target, in: originalDisplays)
            if target.online != plan.target.online { try applyConnection(target, enabled: plan.target.online) }
            try waitFor(plan.target.identity, enabled: plan.target.online)
            try restoreLayout(target: plan.target.online ? plan.target.identity : nil,
                              placement: saved, protectedDisplays: plan.protectedDisplays)
            usleep(150_000)
            let recovered = try displays()
            return recovered.first(where: { plan.target.identity.matches($0) })?.online == plan.target.online
                && plan.otherDisplaysPreserved(in: recovered)
        } catch {
            return false
        }
    }

    private func check(_ error: CGError, _ action: String) throws {
        guard error == .success else { throw SwitchError.system(action, error.rawValue) }
    }
}
