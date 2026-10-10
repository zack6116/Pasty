import AppKit
import PastyCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store: ClipboardStore
    private let monitor = ClipboardMonitor()
    private let hotkey = HotkeyManager()
    private var panelController: HistoryPanelController!
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem!

    override init() {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pasty", isDirectory: true)
        store = ClipboardStore(fileURL: directory.appendingPathComponent("history.json"))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = HistoryPanelController(store: store, monitor: monitor)
        monitor.onChange = { [weak self] text in
            self?.store.add(text)
            self?.panelController.reload()
        }
        monitor.start()
        if let existing = monitor.existingPlainText(), !store.contains(existing) {
            store.add(existing)
        }

        hotkey.onHotkey = { [weak self] in
            self?.panelController.toggle()
        }
        if !hotkey.register() {
            presentAlert(
                title: "无法注册快捷键",
                message: "Command+Shift+V 可能已被其他应用占用。"
            )
        }
        setupStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
        hotkey.unregister()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        panelController.hide()
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Pasty")
            button.toolTip = "Pasty 剪贴板历史"
        }

        let menu = NSMenu()
        menu.delegate = self

        let showItem = NSMenuItem(title: "显示历史    ⌘⇧V", action: #selector(showHistory), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let clearItem = NSMenuItem(title: "清空历史", action: #selector(clearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        launchAtLoginItem = NSMenuItem(title: "登录时打开", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func showHistory() {
        panelController.show()
    }

    @objc private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空历史？"
        alert.informativeText = "这会删除全部复制记录。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        activateForAlert()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clear()
        panelController.reload()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
                if service.status == .requiresApproval {
                    presentAlert(
                        title: "需要允许登录时打开",
                        message: "请到「系统设置 › 通用 › 登录项与扩展」里允许 Pasty。"
                    )
                }
            }
        } catch {
            presentAlert(
                title: "无法设置登录时打开",
                message: "请把 Pasty.app 放到「应用程序」文件夹后再试。\n\(error.localizedDescription)"
            )
        }
        launchAtLoginItem.state = service.status == .enabled ? .on : .off
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        activateForAlert()
        alert.runModal()
    }

    private func activateForAlert() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
