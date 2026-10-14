import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: ProjectorController?
    private var shortcut: GlobalShortcut?
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var screenObserver: NSObjectProtocol?
    private var feedbackPanel: NSPanel?
    private var dismissFeedback: DispatchWorkItem?
    private var lastError: String?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            other.activate(options: [])
            NSApp.terminate(nil)
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        item.menu = menu
        item.button?.toolTip = "苹果电脑投影开关"
        menu.delegate = self
        do {
            controller = ProjectorController(store: try SettingsStore(), service: try DisplayService())
            let binding = try GlobalShortcut()
            shortcut = binding
            binding.action = { [weak self] in self?.toggleProjector(nil) }
            let choice = ShortcutChoice(rawValue: controller!.store.settings.shortcut) ?? .option
            do { try binding.register(choice) } catch { lastError = error.localizedDescription }
        } catch {
            lastError = error.localizedDescription
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.updateIcon() }
        rebuildMenu()
        if let error = lastError { showAlert(error) }
        else { showFeedback("苹果电脑投影开关已就绪", detail: "\(shortcut?.choice?.title ?? "菜单栏") 切换指定投影仪") }
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        menu.removeAllItems()
        var current: DisplayRecord?
        var displays: [DisplayRecord] = []
        if let controller {
            do {
                displays = try controller.service.displays()
                current = displays.first { controller.store.settings.target?.matches($0) == true }
            } catch { lastError = error.localizedDescription }
        }
        let name = controller?.store.settings.target?.name ?? "尚未选择"
        add("投影仪：\(name)", enabled: false)
        add(current.map { $0.online ? "已启用 · \($0.width) × \($0.height)" : "已停用" } ?? "暂时未找到设备", enabled: false)
        if let lastError { add(lastError, enabled: false) }
        menu.addItem(.separator())
        let toggle = add(current?.online == true ? "停用投影仪" : "启用投影仪",
                         action: #selector(toggleProjector(_:)), enabled: current != nil && controller?.busy != true)
        if let choice = shortcut?.choice {
            toggle.keyEquivalent = "p"
            switch choice {
            case .option: toggle.keyEquivalentModifierMask = [.option]
            case .commandOption: toggle.keyEquivalentModifierMask = [.command, .option]
            case .controlOption: toggle.keyEquivalentModifierMask = [.control, .option]
            case .controlShift: toggle.keyEquivalentModifierMask = [.control, .shift]
            }
        }
        add("恢复投影仪", action: #selector(restoreProjector(_:)), enabled: current?.online == false)

        let selection = NSMenu()
        for display in displays.filter({ !$0.builtIn && (!$0.identity.uuid.hasPrefix("unavailable-")
            || controller?.store.settings.target?.matches($0) == true) }) {
            let suffix = display.main ? "（主显示器）" : (display.online ? "" : "（已停用）")
            let selected = controller?.store.settings.target?.matches(display) == true
            let name = selected ? (controller?.store.settings.target?.name ?? display.identity.name) : display.identity.name
            let item = NSMenuItem(title: name + suffix, action: #selector(selectProjector(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = display
            item.state = selected ? .on : .off
            item.isEnabled = !display.identity.uuid.hasPrefix("unavailable-")
            selection.addItem(item)
        }
        if selection.items.isEmpty { selection.addItem(withTitle: "没有可选择的外接设备", action: nil, keyEquivalent: "") }
        let select = add("选择投影仪…")
        select.submenu = selection

        let keys = NSMenu()
        for choice in ShortcutChoice.allCases {
            let item = NSMenuItem(title: choice.title, action: #selector(changeShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = choice.rawValue
            item.state = shortcut?.choice == choice ? .on : .off
            keys.addItem(item)
        }
        let keyItem = add("快捷键", enabled: shortcut != nil)
        keyItem.submenu = keys
        menu.addItem(.separator())
        add("使用说明", action: #selector(showHelp(_:)))
        add("退出并恢复投影仪", action: #selector(quit(_:)))
        updateIcon(current)
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.addItem(item)
        return item
    }

    private func updateIcon(_ known: DisplayRecord? = nil) {
        let current = known ?? (try? controller?.selectedDisplay())
        let symbol = current?.online == true ? "videoprojector" : "videoprojector.fill"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "苹果电脑投影开关")
            ?? NSImage(systemSymbolName: "display", accessibilityDescription: "苹果电脑投影开关")
        image?.isTemplate = true
        statusItem?.button?.image = image
        if image == nil { statusItem?.button?.title = "投" }
        statusItem?.button?.toolTip = "苹果电脑投影开关 · \(current?.online == true ? "投影仪已启用" : "投影仪未启用")"
        RuntimeDiagnostics(pid: ProcessInfo.processInfo.processIdentifier,
            shortcut: shortcut?.choice?.title, shortcutRegistered: shortcut?.choice != nil,
            target: controller?.store.settings.target?.name, projectorOnline: current?.online,
            lastError: lastError).save()
    }

    @objc private func toggleProjector(_ sender: Any?) {
        perform { controller in try controller.toggle() }
    }

    @objc private func restoreProjector(_ sender: Any?) {
        perform { controller in try controller.setEnabled(true) }
    }

    private func perform(_ operation: @escaping (ProjectorController) throws -> DisplayRecord) {
        guard let controller, !controller.busy else { return }
        // Let the menu close before WindowServer changes the screen topology.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            do {
                let result = try operation(controller)
                self.lastError = nil
                self.rebuildMenu()
                self.showFeedback(result.online ? "投影仪已启用" : "投影仪已停用", detail: result.identity.name)
            } catch {
                self.lastError = error.localizedDescription
                self.rebuildMenu()
                self.showAlert(error.localizedDescription)
            }
        }
    }

    @objc private func selectProjector(_ sender: NSMenuItem) {
        guard let controller, let record = sender.representedObject as? DisplayRecord else { return }
        do {
            try controller.select(record)
            lastError = nil
            rebuildMenu()
            showFeedback("已选择投影仪", detail: record.identity.name)
        } catch { showAlert(error.localizedDescription) }
    }

    @objc private func changeShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = ShortcutChoice(rawValue: raw),
              let shortcut, let controller else { return }
        let previous = shortcut.choice
        do {
            try shortcut.register(choice)
            do { try controller.store.update { $0.shortcut = choice.rawValue } }
            catch {
                if let previous { try? shortcut.register(previous) }
                throw error
            }
            lastError = nil
            rebuildMenu()
            showFeedback("快捷键已更新", detail: choice.title)
        } catch { showAlert(error.localizedDescription) }
    }

    @objc private func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "苹果电脑投影开关"
        alert.informativeText = "按 \(shortcut?.choice?.title ?? "菜单中的切换按钮") 启用或停用指定投影仪。\n\n首次使用可在“选择投影仪”中确认设备。切换不控制投影仪的电源。\n\n睡眠唤醒后，macOS 可能重新启用投影仪；再按一次快捷键即可停用。\n\n正常退出会恢复本次由小工具停用的投影仪。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showAlert(_ text: String) {
        let alert = NSAlert()
        alert.messageText = "苹果电脑投影开关"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showFeedback(_ title: String, detail: String) {
        dismissFeedback?.cancel()
        feedbackPanel?.close()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 90),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let background = NSVisualEffectView(frame: panel.contentView!.bounds)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.frame = NSRect(x: 12, y: 45, width: 256, height: 26)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.frame = NSRect(x: 12, y: 20, width: 256, height: 22)
        background.addSubview(titleLabel)
        background.addSubview(detailLabel)
        panel.contentView = background
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - 140, y: frame.minY + 55))
        }
        panel.orderFrontRegardless()
        feedbackPanel = panel
        let dismiss = DispatchWorkItem { [weak self, weak panel] in
            panel?.close()
            self?.feedbackPanel = nil
        }
        dismissFeedback = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: dismiss)
    }

    @objc private func quit(_ sender: Any?) {
        if let controller, (try? controller.selectedDisplay()?.online) == false {
            do { _ = try controller.setEnabled(true) }
            catch { showAlert(error.localizedDescription); return }
        }
        isQuitting = true
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitting, let controller, controller.disabledByThisRun,
              (try? controller.selectedDisplay()?.online) == false else { return .terminateNow }
        do { _ = try controller.setEnabled(true); return .terminateNow }
        catch { showAlert(error.localizedDescription); return .terminateCancel }
    }

    deinit { if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) } }
}
