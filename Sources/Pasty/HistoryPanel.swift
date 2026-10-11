import AppKit
import Combine
import PastyCore
import SwiftUI

enum HistoryPanelMetrics {
    static let width: CGFloat = 440
    static let height: CGFloat = 520
    static let previewWidth: CGFloat = 680
    static let previewHeight: CGFloat = 720
    static let cornerRadius: CGFloat = 16
}

final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: HistoryPanelMetrics.width, height: HistoryPanelMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
        isRestorable = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = false
    }
}

final class HistoryPanelController {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor
    private let model = HistoryModel()
    private let panel = HistoryPanel()
    private var keyMonitor: Any?
    private var clickMonitor: Any?

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        let historyStore = store
        let hosting = NSHostingView(rootView: HistoryView(
            model: model,
            imageURL: { item in historyStore.imageURL(for: item) },
            onCopy: { [weak self] item in
                self?.copy(item)
            },
            onDelete: { [weak self] item in
                self?.delete(item)
            }
        ))
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = HistoryPanelMetrics.cornerRadius
        hosting.layer?.masksToBounds = true
        hosting.sizingOptions = []
        panel.contentView = hosting
        model.$isPreviewing
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] previewing in
                guard let self, self.panel.isVisible else { return }
                self.resize(previewing: previewing, animated: true)
            }
            .store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        model.prepare(store.items)
        positionNearMouse()
        installMonitors()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.invalidateShadow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.requestFocus()
            if let textField = self.findTextField(in: self.panel.contentView) {
                self.panel.makeFirstResponder(textField)
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
        let monitors = [keyMonitor, clickMonitor].compactMap { $0 }
        keyMonitor = nil
        clickMonitor = nil
        DispatchQueue.main.async {
            monitors.forEach(NSEvent.removeMonitor)
        }
    }

    func reload() {
        guard panel.isVisible else { return }
        model.reload(store.items)
    }

    private func copy(_ item: ClipItem) {
        if item.isImage {
            guard let data = store.imageData(for: item) else { return }
            monitor.writeImage(data)
        } else {
            monitor.write(item.text)
        }
        hide()
    }

    private func delete(_ item: ClipItem) {
        guard store.delete(id: item.id) else { return }
        model.remove(item.id)
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: HistoryPanelMetrics.width, height: HistoryPanelMetrics.height)

        var origin = NSPoint(x: mouse.x - size.width / 2, y: mouse.y - 12 - size.height)
        if origin.y < visible.minY + 8 {
            origin.y = mouse.y + 12
        }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func resize(previewing: Bool, animated: Bool) {
        let desired = previewing
            ? NSSize(width: HistoryPanelMetrics.previewWidth, height: HistoryPanelMetrics.previewHeight)
            : NSSize(width: HistoryPanelMetrics.width, height: HistoryPanelMetrics.height)
        let current = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(current) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? current
        let size = NSSize(
            width: min(desired.width, max(320, visible.width - 16)),
            height: min(desired.height, max(360, visible.height - 16))
        )
        var origin = NSPoint(x: current.midX - size.width / 2, y: current.midY - size.height / 2)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        let frame = NSRect(origin: origin, size: size)
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            self?.hide()
        }
    }

    private func removeMonitors() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
            self.clickMonitor = nil
        }
    }

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        if fieldEditorHasMarkedText() {
            return false
        }
        switch event.keyCode {
        case 126: // up
            model.moveSelection(by: -1)
            return true
        case 125: // down
            model.moveSelection(by: 1)
            return true
        case 36, 76: // return, keypad enter
            if let item = model.selectedItem {
                copy(item)
            } else {
                hide()
            }
            return true
        case 49 where event.modifierFlags.intersection([.command, .option, .control]).isEmpty:
            if event.isARepeat { return true }
            if !model.query.isEmpty {
                return false
            }
            model.togglePreview()
            return true
        case 53: // escape
            if model.isPreviewing {
                model.closePreview()
            } else {
                hide()
            }
            return true
        default:
            return false
        }
    }

    private func fieldEditorHasMarkedText() -> Bool {
        guard let client = panel.firstResponder as? NSTextInputClient else { return false }
        return client.hasMarkedText()
    }

    private func findTextField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let textField = view as? NSTextField { return textField }
        for subview in view.subviews {
            if let textField = findTextField(in: subview) { return textField }
        }
        return nil
    }
}
