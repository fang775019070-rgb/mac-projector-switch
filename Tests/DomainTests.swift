import Foundation

@main
struct DomainTests {
    static var passed = 0

    static func display(_ id: UInt32, uuid: String, name: String = "Display", builtin: Bool = false,
                        online: Bool = true, active: Bool = true, main: Bool = false,
                        mirrorOf: UInt32 = 0, x: Int32 = 0, vendor: UInt32 = 10,
                        model: UInt32 = 20, serial: UInt32 = 1) -> DisplayRecord {
        DisplayRecord(id: id, identity: DisplayIdentity(uuid: uuid, vendor: vendor, model: model,
            serial: serial, name: name), builtIn: builtin, online: online, active: active,
            main: main, mirrorOf: mirrorOf, x: x, y: 0, width: 1920, height: 1080, refreshRate: 60)
    }

    static func test(_ name: String, _ action: () throws -> Void) throws {
        try action()
        passed += 1
        print("PASS: \(name)")
    }

    static func check(_ condition: Bool) throws {
        if !condition { throw SwitchError.message("断言失败") }
    }

    static func rejects(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw SwitchError.message("操作本应被拒绝")
    }

    static func main() throws {
        let projector = display(3, uuid: "projector", name: "Projector", x: 1920)
        let monitor = display(2, uuid: "monitor", name: "Desk Monitor", main: true, model: 21)
        let builtin = display(1, uuid: "builtin", builtin: true, x: -1920)
        try test("Only the bound projector is targeted in a three-screen setup") {
            let plan = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [monitor, builtin, projector])
            try check(plan.target.id == 3 && Set(plan.protectedDisplays.map(\.id)) == [1, 2])
        }
        try test("A changed numeric display ID still resolves by current hardware identity") {
            let newID = display(77, uuid: "projector", name: "Projector", x: 1920)
            let plan = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [monitor, newID])
            try check(plan.target.id == 77)
        }
        try test("A recycled display ID cannot select the other monitor") {
            let recycled = display(3, uuid: "monitor", name: "Projector")
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [recycled, builtin]) }
        }
        try test("Display names alone never determine the target") {
            let sameName = display(5, uuid: "different", name: "Projector")
            let plan = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [sameName, monitor, projector])
            try check(plan.target.id == 3)
        }
        try test("A duplicated identity is refused rather than guessing") {
            let duplicate = display(6, uuid: "projector")
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [projector, duplicate, monitor]) }
        }
        try test("A hardware mismatch blocks a reused UUID") {
            let mismatch = display(3, uuid: "projector", vendor: 999)
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [mismatch, monitor]) }
        }
        try test("The internal screen cannot be bound or disabled") {
            try rejects { _ = try DisplayPlan.make(target: builtin.identity, enabled: false, displays: [builtin, monitor]) }
        }
        try test("The last usable screen cannot be disabled") {
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [projector]) }
        }
        try test("A mirrored copy does not count as an independent remaining screen") {
            let copy = display(2, uuid: "copy", active: false, mirrorOf: 3)
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [projector, copy]) }
        }
        try test("A main projector is refused to preserve the other monitor's main status") {
            let main = display(3, uuid: "projector", main: true)
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [main, builtin]) }
        }
        try test("A projector driving other mirrored screens is refused") {
            let copy = display(8, uuid: "copy", mirrorOf: 3)
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [projector, monitor, copy]) }
        }
        try test("A live but inactive mirror slave is treated as enabled") {
            let slave = display(3, uuid: "projector", active: false, mirrorOf: 2)
            let plan = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [monitor, slave])
            try check(plan.target.online && !plan.target.active)
        }
        try test("A disabled projector can be enabled without touching the active monitor") {
            let offline = display(9, uuid: "projector", online: false, active: false)
            let plan = try DisplayPlan.make(target: projector.identity, enabled: true, displays: [offline, monitor])
            try check(plan.enabled && plan.target.id == 9 && plan.protectedDisplays == [monitor])
        }
        try test("A hidden UUID can recover only a currently enumerated exact hardware match") {
            let hidden = display(91, uuid: "unavailable-91", online: false, active: false)
            let plan = try DisplayPlan.make(target: projector.identity, enabled: true, displays: [hidden, monitor])
            try check(plan.target.id == 91)
        }
        try test("Ambiguous hardware metadata is refused when the offline UUID is hidden") {
            let hidden = display(91, uuid: "unavailable-91", online: false, active: false)
            let identical = display(92, uuid: "different-projector")
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: true, displays: [hidden, identical]) }
        }
        try test("Missing UUID on an online screen cannot impersonate the projector") {
            let unknown = display(91, uuid: "unavailable-91")
            try rejects { _ = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [unknown, monitor]) }
        }
        try test("Post-check notices if the other monitor is missing or its layout changes") {
            let plan = try DisplayPlan.make(target: projector.identity, enabled: false, displays: [projector, monitor, builtin])
            try check(plan.otherDisplaysPreserved(in: [monitor, builtin]))
            try check(!plan.otherDisplaysPreserved(in: [builtin]))
            let moved = display(2, uuid: "monitor", main: true, x: 100)
            try check(!plan.otherDisplaysPreserved(in: [moved, builtin]))
        }
        try test("Target settings round-trip with recovery placement") {
            let root = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let url = root.appendingPathComponent("settings.json")
            let store = try SettingsStore(url: url)
            try check(store.settings.target == nil && store.settings.shortcut == "option")
            try store.update {
                $0.target = projector.identity
                $0.placement = SavedPlacement(x: 1920, y: 0, mirrorSourceUUID: nil)
            }
            let reloaded = try SettingsStore(url: url)
            try check(reloaded.settings.target == projector.identity && reloaded.settings.placement?.x == 1920)
        }
        print("\(passed) meaningful safety and persistence checks passed.")
    }
}
