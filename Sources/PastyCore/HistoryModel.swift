import Combine
import Foundation

public final class HistoryModel: ObservableObject {
    @Published public private(set) var items: [ClipItem] = []
    @Published public var query: String = ""
    @Published public private(set) var selectedID: UUID?
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

    public func selectedText() -> String? {
        let visible = filtered
        if let selectedID, let item = visible.first(where: { $0.id == selectedID }) {
            return item.text
        }
        return visible.first?.text
    }

    private func clampSelection() {
        let visible = filtered
        if let selectedID, visible.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = visible.first?.id
    }
}
