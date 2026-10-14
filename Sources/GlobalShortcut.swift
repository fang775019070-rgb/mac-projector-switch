import Carbon
import Foundation

enum ShortcutChoice: String, CaseIterable {
    case option = "option"
    case commandOption = "command-option"
    case controlOption = "control-option"
    case controlShift = "control-shift"

    var title: String {
        switch self {
        case .option: return "⌥P"
        case .commandOption: return "⌥⌘P"
        case .controlOption: return "⌃⌥P"
        case .controlShift: return "⌃⇧P"
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .option: return UInt32(optionKey)
        case .commandOption: return UInt32(cmdKey | optionKey)
        case .controlOption: return UInt32(controlKey | optionKey)
        case .controlShift: return UInt32(controlKey | shiftKey)
        }
    }
}

final class GlobalShortcut {
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private(set) var choice: ShortcutChoice?
    var action: (() -> Void)?
    private var lastPress: TimeInterval = 0

    init() throws {
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x50524A53, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            shortcut.pressed()
            return noErr
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw SwitchError.message("无法注册全局快捷键。菜单栏开关仍可使用。") }
    }

    func register(_ proposed: ShortcutChoice) throws {
        let previous = choice
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        choice = nil
        let identifier = EventHotKeyID(signature: 0x50524A53, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_P), proposed.modifiers,
            identifier, GetApplicationEventTarget(), 0, &hotKey)
        guard status == noErr else {
            if let previous {
                let recovery = RegisterEventHotKey(UInt32(kVK_ANSI_P), previous.modifiers,
                    identifier, GetApplicationEventTarget(), 0, &hotKey)
                if recovery == noErr { choice = previous }
            }
            throw SwitchError.message("\(proposed.title) 已被占用或无法注册。请在菜单中换一组快捷键。")
        }
        choice = proposed
    }

    private func pressed() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPress > 0.8 else { return }
        lastPress = now
        DispatchQueue.main.async { [weak self] in self?.action?() }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
