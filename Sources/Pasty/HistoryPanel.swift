import AppKit
import Combine
import PastyCore
import SwiftUI

enum HistoryPanelMetrics {
    static let width: CGFloat = 880
    static let height: CGFloat = 340
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
    private var scrollMonitor: Any?
    private var scrollAccumulated: CGFloat = 0

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
            },
            onAssign: { [weak self] item, boardID in
                self?.assign(item, boardID: boardID)
            },
            onUnpin: { [weak self] item in
                self?.assign(item, boardID: nil)
            },
            onPinHere: { [weak self] item in
                self?.togglePin(item)
            },
            onAddBoard: { [weak self] name in
                self?.addBoard(name)
            },
            onRenameBoard: { [weak self] id, name in
                self?.renameBoard(id, name: name)
            },
            onDeleteBoard: { [weak self] id in
                self?.deleteBoard(id)
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

    func show(shelf: HistoryShelf = .recent) {
        model.prepare(store.items, boards: store.boards, shelf: shelf)
        guard !panel.isVisible else {
            panel.makeKey()
            return
        }
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
        scrollAccumulated = 0
        let monitors = [keyMonitor, clickMonitor, scrollMonitor].compactMap { $0 }
        keyMonitor = nil
        clickMonitor = nil
        scrollMonitor = nil
        DispatchQueue.main.async {
            monitors.forEach(NSEvent.removeMonitor)
        }
    }

    func reload() {
        guard panel.isVisible else { return }
        model.reload(store.items, boards: store.boards)
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

    private func togglePin(_ item: ClipItem) {
        if item.boardID != nil {
            assign(item, boardID: nil)
            return
        }
        if case .board(let id) = model.shelf {
            assign(item, boardID: id)
            return
        }
        if let board = store.boards.first {
            assign(item, boardID: board.id)
            return
        }
        guard let board = store.addBoard(name: ClipboardStore.defaultBoardName) else { return }
        assign(item, boardID: board.id)
    }

    private func assign(_ item: ClipItem, boardID: UUID?) {
        guard store.assign(id: item.id, boardID: boardID) else { return }
        model.applyAssignment(id: item.id, boardID: boardID)
        let selected = model.selectedID
        model.reload(store.items, boards: store.boards)
        if let selected {
            model.select(selected)
        }
    }

    private func addBoard(_ name: String) {
        guard let board = store.addBoard(name: name) else { return }
        model.reload(store.items, boards: store.boards)
        model.showBoard(board.id)
    }

    private func renameBoard(_ id: UUID, name: String) {
        guard store.renameBoard(id: id, name: name) else { return }
        model.reload(store.items, boards: store.boards)
    }

    private func deleteBoard(_ id: UUID) {
        guard store.deleteBoard(id: id) else { return }
        model.reload(store.items, boards: store.boards)
    }

    private func positionNearMouse() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(
            width: min(HistoryPanelMetrics.width, max(360, visible.width - 16)),
            height: min(HistoryPanelMetrics.height, max(240, visible.height - 16))
        )

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
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            return self.handleScroll(event) ? nil : event
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
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }

    /// Vertical scrolling moves the selection the same way the left and right arrow keys do.
    private func handleScroll(_ event: NSEvent) -> Bool {
        if model.isPreviewing { return false }
        if event.momentumPhase == .began || event.momentumPhase == .changed || event.momentumPhase == .ended {
            return true
        }
        if event.phase == .began {
            scrollAccumulated = 0
        }
        let steps = ScrollSelection.consume(
            deltaY: event.scrollingDeltaY,
            precise: event.hasPreciseScrollingDeltas,
            accumulated: &scrollAccumulated
        )
        if steps != 0 {
            model.moveSelection(by: steps)
        }
        return true
    }

    /// Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        if fieldEditorHasMarkedText() {
            return false
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "p":
                if let item = model.selectedItem {
                    togglePin(item)
                }
                return true
            case "1":
                model.showRecent()
                return true
            case "2", "3", "4", "5", "6", "7", "8", "9":
                if let digit = event.charactersIgnoringModifiers.flatMap({ Int($0) }) {
                    let index = digit - 2
                    if model.boards.indices.contains(index) {
                        model.showBoard(model.boards[index].id)
                    }
                }
                return true
            default:
                break
            }
        }
        switch event.keyCode {
        case 123, 126: // left, up
            model.moveSelection(by: -1)
            return true
        case 124, 125: // right, down
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
