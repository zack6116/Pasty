import Combine
import Foundation

public final class HistoryModel: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []
    @Published public var query: String = ""
    @Published public private(set) var selectedID: UUID?
    @Published public private(set) var isPreviewing = false
    @Published public private(set) var focusToken = 0

    public var filtered: [ClipItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.text.localizedCaseInsensitiveContains(trimmed) }
    }

    private var cancellables = Set<AnyCancellable>()

    public init() {
        $query.sink { [weak self] _ in
            self?.clampSelection()
        }
        .store(in: &cancellables)
    }

    public func prepare(_ items: [ClipItem]) {
        self.items = items
        query = ""
        selectedID = items.first?.id
        isPreviewing = false
    }

    public func reload(_ items: [ClipItem]) {
        let previous = selectedID
        self.items = items
        if let previous, filtered.contains(where: { $0.id == previous }) {
            selectedID = previous
        } else {
            selectedID = filtered.first?.id
        }
    }

    public func requestFocus() {
        focusToken += 1
    }

    public func moveSelection(by delta: Int) {
        let visible = filtered
        guard !visible.isEmpty else {
            selectedID = nil
            return
        }
        guard let selectedID, let index = visible.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = delta >= 0 ? visible.first?.id : visible.last?.id
            return
        }
        let next = min(max(index + delta, 0), visible.count - 1)
        self.selectedID = visible[next].id
    }

    public func select(_ id: UUID) {
        guard filtered.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Drops one row. The selection moves to the following visible row, or the previous one at the end.
    public func remove(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        let visible = filtered
        let wasSelected = selectedID == id
        var neighbor: UUID?
        if wasSelected, let index = visible.firstIndex(where: { $0.id == id }) {
            if index + 1 < visible.count {
                neighbor = visible[index + 1].id
            } else if index > 0 {
                neighbor = visible[index - 1].id
            }
        }
        items.removeAll { $0.id == id }
        if wasSelected {
            selectedID = neighbor
            isPreviewing = false
        }
    }

    public var selectedItem: ClipItem? {
        let visible = filtered
        if let selectedID, let item = visible.first(where: { $0.id == selectedID }) {
            return item
        }
        return visible.first
    }

    public func selectedText() -> String? {
        selectedItem?.text
    }

    public func togglePreview() {
        guard selectedItem != nil else {
            isPreviewing = false
            return
        }
        isPreviewing.toggle()
    }

    public func closePreview() {
        isPreviewing = false
    }

    private func clampSelection() {
        let visible = filtered
        if let selectedID, visible.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visible.first?.id
    }
}
