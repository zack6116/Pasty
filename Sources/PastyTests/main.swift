import AppKit
import Foundation
import PastyCore

private var failures = 0

private func check(
    _ condition: @autoclosure () -> Bool,
    _ message: String,
    file: StaticString = #file,
    line: UInt = #line
) {
    if !condition() {
        failures += 1
        fputs("FAIL \(file):\(line) \(message)\n", stderr)
    }
}

private func withStore(_ body: (ClipboardStore) -> Void) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    body(ClipboardStore(fileURL: directory.appendingPathComponent("history.json")))
}

private func testAddPlacesNewestFirstAndSkipsBlankText() {
    withStore { store in
        let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
        let secondDate = Date(timeIntervalSince1970: 1_700_000_100)
        check(store.add("   \n\t", at: firstDate) == false, "blank text is rejected")
        check(store.items.isEmpty, "blank text does not create an item")
        check(store.add("alpha", at: firstDate), "alpha is stored")
        check(store.add("beta", at: secondDate), "beta is stored")
        check(store.items.map(\.text) == ["beta", "alpha"], "newest copy is first")
        check(store.items.map(\.copiedAt) == [secondDate, firstDate], "timestamps follow copy order")
    }
}

private func testDuplicateTextMovesExistingItemToFront() {
    withStore { store in
        store.add("alpha", at: Date(timeIntervalSince1970: 1_700_000_000))
        store.add("beta", at: Date(timeIntervalSince1970: 1_700_000_100))
        store.add("gamma", at: Date(timeIntervalSince1970: 1_700_000_200))
        let originalID = store.items.first { $0.text == "beta" }?.id
        let reusedAt = Date(timeIntervalSince1970: 1_700_000_300)

        check(store.add("beta", at: reusedAt), "duplicate copy is accepted")
        check(store.items.map(\.text) == ["beta", "gamma", "alpha"], "duplicate moves to front")
        check(store.items[0].id == originalID, "duplicate keeps its original id")
        check(store.items[0].copiedAt == reusedAt, "duplicate refreshes its timestamp")
        check(store.items.count == 3, "duplicate does not create another row")
    }
}

private func testItemsAreCappedAtOneHundred() {
    withStore { store in
        for index in 0..<120 {
            store.add("item-\(index)", at: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)))
        }
        check(store.items.count == ClipboardStore.maxItems, "history is capped at 100")
        check(store.items.first?.text == "item-119", "newest item is kept")
        check(store.items.last?.text == "item-20", "oldest items are dropped")
    }
}

private func testDuplicateAtCapacityDoesNotDropOtherItems() {
    withStore { store in
        for index in 0..<100 {
            store.add("item-\(index)", at: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index)))
        }
        store.add("item-5", at: Date(timeIntervalSince1970: 1_700_000_500))
        check(store.items.count == 100, "re-copying at capacity stays at 100")
        check(store.items.first?.text == "item-5", "re-copied item moves to front")
        check(store.items.contains { $0.text == "item-0" }, "oldest item remains")
        check(store.items.contains { $0.text == "item-99" }, "previous newest item remains")
    }
}

private func testHistoryRoundTripsThroughJSON() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = ClipboardStore(fileURL: fileURL)
    store.add("older", at: Date(timeIntervalSince1970: 1_700_000_000))
    store.add("newer", at: Date(timeIntervalSince1970: 1_700_000_050))

    let reloaded = ClipboardStore(fileURL: fileURL)
    check(reloaded.items == store.items, "history survives a reload")
}

private func testClearRemovesPersistedHistory() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = ClipboardStore(fileURL: fileURL)
    store.add("keep-me", at: Date(timeIntervalSince1970: 1_700_000_000))
    store.clear()

    let reloaded = ClipboardStore(fileURL: fileURL)
    check(store.items.isEmpty, "clear removes items from memory")
    check(reloaded.items.isEmpty, "clear removes items from disk")
}

private func testBlankTextDoesNotEraseExistingHistory() {
    withStore { store in
        store.add("alpha", at: Date(timeIntervalSince1970: 1_700_000_000))
        check(store.add(" \n ", at: Date(timeIntervalSince1970: 1_700_000_100)) == false, "blank text is ignored")
        check(store.items.map(\.text) == ["alpha"], "existing history stays in place")
    }
}

private func privatePasteboard() -> NSPasteboard {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("pasty-tests-\(UUID().uuidString)"))
    pasteboard.clearContents()
    return pasteboard
}

private func testMonitorRecordsExternalCopiesAndSkipsItsOwnWrite() {
    let pasteboard = privatePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, interval: 60)
    var seen: [String] = []
    monitor.onChange = { seen.append($0) }

    pasteboard.clearContents()
    pasteboard.setString("from-outside", forType: .string)
    monitor.checkForChanges()
    check(seen == ["from-outside"], "external copy is recorded")

    seen.removeAll()
    monitor.write("from-pasty")
    monitor.checkForChanges()
    check(seen.isEmpty, "writing the pasteboard does not record another history item")

    pasteboard.clearContents()
    pasteboard.setString("later", forType: .string)
    monitor.checkForChanges()
    check(seen == ["later"], "copies after our own write are still recorded")
}

private func testMonitorSkipsBlankAndConcealedContents() {
    let pasteboard = privatePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, interval: 60)
    var seen: [String] = []
    monitor.onChange = { seen.append($0) }

    pasteboard.clearContents()
    pasteboard.setString("   \n", forType: .string)
    monitor.checkForChanges()
    check(seen.isEmpty, "blank pasteboard contents are skipped")

    pasteboard.clearContents()
    let concealed = NSPasteboardItem()
    concealed.setString("secret", forType: .string)
    concealed.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pasteboard.writeObjects([concealed])
    monitor.checkForChanges()
    check(seen.isEmpty, "concealed pasteboard contents are skipped")
    check(monitor.existingPlainText() == nil, "concealed contents are not imported at launch")
}

private func testSelectionMovesAndSearchFilters() {
    withStore { store in
        store.add("Alpha", at: Date(timeIntervalSince1970: 1_700_000_000))
        store.add("beta", at: Date(timeIntervalSince1970: 1_700_000_100))
        let model = HistoryModel()
        model.prepare(store.items)

        check(model.selectedText() == "beta", "the panel opens on the newest item")
        model.moveSelection(by: 1)
        check(model.selectedText() == "Alpha", "down arrow moves to the older item")
        model.moveSelection(by: 1)
        check(model.selectedText() == "Alpha", "down arrow stops at the end")
        model.moveSelection(by: -1)
        check(model.selectedText() == "beta", "up arrow moves back")

        model.query = "alp"
        check(model.filtered.map(\.text) == ["Alpha"], "search is case-insensitive")
        check(model.selectedText() == "Alpha", "search selects the remaining match")
        model.query = "missing"
        check(model.filtered.isEmpty, "unmatched search shows nothing")
        check(model.selectedText() == nil, "unmatched search has nothing to copy")
    }
}

testAddPlacesNewestFirstAndSkipsBlankText()
testDuplicateTextMovesExistingItemToFront()
testItemsAreCappedAtOneHundred()
testDuplicateAtCapacityDoesNotDropOtherItems()
testHistoryRoundTripsThroughJSON()
testClearRemovesPersistedHistory()
testBlankTextDoesNotEraseExistingHistory()
testMonitorRecordsExternalCopiesAndSkipsItsOwnWrite()
testMonitorSkipsBlankAndConcealedContents()
testSelectionMovesAndSearchFilters()

if failures > 0 {
    fputs("\(failures) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
