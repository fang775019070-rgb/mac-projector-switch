import AppKit
import Carbon
import Foundation

@main
struct ShortcutTests {
    static func main() throws {
        _ = NSApplication.shared
        let binding = try GlobalShortcut()
        var calls = 0
        binding.action = { calls += 1 }
        try binding.register(.option)
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else {
            throw SwitchError.message("无法创建内部测试事件")
        }
        defer { ReleaseEvent(event) }
        var identifier = EventHotKeyID(signature: 0x50524A53, id: 1)
        guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size, &identifier) == noErr else {
            throw SwitchError.message("无法设置内部测试事件")
        }
        let result = SendEventToEventTarget(event, GetApplicationEventTarget())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard result == noErr && calls == 1 else { throw SwitchError.message("快捷键回调没有正确触发") }
        // A held/repeated press must not immediately toggle the display a second time.
        _ = SendEventToEventTarget(event, GetApplicationEventTarget())
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        guard calls == 1 else { throw SwitchError.message("快捷键重复按下保护失败") }
        print("PASS: Option+P registration, callback dispatch and held-key protection")
    }
}
