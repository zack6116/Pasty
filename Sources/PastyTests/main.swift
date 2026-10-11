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

private func testDeleteRemovesOneItemAndItsImage() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = ClipboardStore(fileURL: fileURL)
    store.add("keep", at: Date(timeIntervalSince1970: 1_700_000_000))
    store.addImage(solidPNG(width: 2, height: 2, red: 9), at: Date(timeIntervalSince1970: 1_700_000_100))
    let image = store.items[0]
    let imageURL = store.imageURL(for: image)!
    let missing = UUID()

    check(store.delete(id: missing) == false, "unknown ids are left alone")
    check(store.items.count == 2, "a missing id does not remove rows")
    check(store.delete(id: image.id), "the chosen image is deleted")
    check(store.items.map(\.text) == ["keep"], "other rows stay")
    check(FileManager.default.fileExists(atPath: imageURL.path) == false, "deleting an image removes its png")

    let reloaded = ClipboardStore(fileURL: fileURL)
    check(reloaded.items.map(\.text) == ["keep"], "a deleted row stays gone after reload")
}

private func testRemovingTheSelectionMovesToTheNextRow() {
    withStore { store in
        store.add("older", at: Date(timeIntervalSince1970: 1_700_000_000))
        store.add("middle", at: Date(timeIntervalSince1970: 1_700_000_100))
        store.add("newer", at: Date(timeIntervalSince1970: 1_700_000_200))
        let model = HistoryModel()
        model.prepare(store.items)
        model.moveSelection(by: 1)
        model.togglePreview()
        let middle = model.selectedItem!

        model.remove(middle.id)
        check(model.items.map(\.text) == ["newer", "older"], "the chosen row leaves the list")
        check(model.selectedText() == "older", "selection moves to the following row")
        check(model.isPreviewing == false, "deleting the open preview closes it")

        model.togglePreview()
        model.remove(model.items[0].id)
        check(model.selectedText() == "older", "deleting another row keeps the current selection")
        check(model.isPreviewing, "a preview of a different row stays open")

        model.remove(model.selectedItem!.id)
        check(model.items.isEmpty, "the last row can be deleted")
        check(model.selectedText() == nil, "an empty list has no selection")
        check(model.isPreviewing == false, "deleting the last previewed row closes the preview")
    }
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

private func solidPNG(width: Int, height: Int, red: UInt8) -> Data {
    let bytesPerRow = width * 4
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: bytesPerRow,
        bitsPerPixel: 32
    )!
    if let pixels = rep.bitmapData {
        for index in 0..<(width * height) {
            pixels[index * 4] = red
            pixels[index * 4 + 1] = 0
            pixels[index * 4 + 2] = 0
            pixels[index * 4 + 3] = 255
        }
    }
    return rep.representation(using: .png, properties: [:])!
}

private func testLegacyHistoryWithoutImageFieldsStillLoads() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let json = """
    [
      {
        "copiedAt" : "2023-11-14T22:13:20Z",
        "id" : "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
        "text" : "legacy"
      }
    ]
    """
    try! json.write(to: fileURL, atomically: true, encoding: .utf8)

    let store = ClipboardStore(fileURL: fileURL)
    check(store.items.map(\.text) == ["legacy"], "legacy history still loads")
    check(store.items[0].isImage == false, "legacy rows stay text")
}

private func testImagesAreStoredDedupedAndRemovedWithHistory() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = ClipboardStore(fileURL: fileURL)
    let firstDate = Date(timeIntervalSince1970: 1_700_000_000)
    let secondDate = Date(timeIntervalSince1970: 1_700_000_100)
    let image = solidPNG(width: 2, height: 3, red: 40)
    let other = solidPNG(width: 4, height: 1, red: 80)

    check(store.addImage(Data("not-a-png".utf8), at: firstDate) == false, "non-png data is rejected")
    check(store.addImage(image, at: firstDate), "image is stored")
    check(store.items[0].isImage, "stored row is an image")
    check(store.items[0].text == "图片\n2×3", "image label includes pixel size")
    check(store.imageData(for: store.items[0]) == image, "png bytes round-trip to disk")
    let originalID = store.items[0].id
    let originalURL = store.imageURL(for: store.items[0])

    store.add("note", at: secondDate)
    check(store.addImage(image, at: secondDate), "the same image is accepted again")
    check(store.items[0].id == originalID, "duplicate image keeps its id")
    check(store.items[0].copiedAt == secondDate, "duplicate image refreshes its timestamp")
    check(store.items.map(\.isImage) == [true, false], "duplicate image moves ahead of text")
    check(store.containsImage(image), "image lookup uses the png contents")
    check(store.contains("note"), "text lookup ignores image labels")

    let reloaded = ClipboardStore(fileURL: fileURL)
    check(reloaded.items == store.items, "image history survives a reload")
    check(reloaded.imageData(for: reloaded.items[0]) == image, "reloaded history still has the png")

    try! FileManager.default.removeItem(at: originalURL!)
    let missing = ClipboardStore(fileURL: fileURL)
    check(missing.items.map(\.text) == ["note"], "a missing image file drops that row")

    store.addImage(other, at: secondDate)
    let imageURL = store.imageURL(for: store.items[0])
    store.clear()
    check(store.items.isEmpty, "clear removes image rows")
    check(FileManager.default.fileExists(atPath: imageURL!.path) == false, "clear deletes the png")
}

private func testImageHistoryDropsTheOldestFileAtCapacity() {
    withStore { store in
        let oldest = solidPNG(width: 1, height: 1, red: 1)
        check(store.addImage(oldest), "first image is stored")
        let oldestURL = store.imageURL(for: store.items[0])!
        for index in 0..<ClipboardStore.maxItems {
            store.addImage(solidPNG(width: 1, height: 1, red: UInt8(index + 2)))
        }
        check(store.items.count == ClipboardStore.maxItems, "image history stays capped")
        check(FileManager.default.fileExists(atPath: oldestURL.path) == false, "the dropped image file is deleted")
        check(store.containsImage(oldest) == false, "the dropped image is gone from history")
    }
}

private func testMonitorRecordsImagesAndSkipsItsOwnWrite() {
    let pasteboard = privatePasteboard()
    let monitor = ClipboardMonitor(pasteboard: pasteboard, interval: 60)
    var images: [Data] = []
    var texts: [String] = []
    monitor.onImage = { images.append($0) }
    monitor.onChange = { texts.append($0) }
    let png = solidPNG(width: 2, height: 2, red: 90)

    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setData(png, forType: .png)
    pasteboard.writeObjects([item])
    monitor.checkForChanges()
    check(images == [png], "png pasteboard contents are recorded")
    check(texts.isEmpty, "an image is not also recorded as text")
    check(monitor.existingImagePNG() == png, "an image already on the pasteboard can be imported")

    images.removeAll()
    monitor.writeImage(png)
    monitor.checkForChanges()
    check(images.isEmpty, "writing an image does not record another history item")

    let tiff = ImagePNG.tiffRepresentation(ofPNG: png)!
    pasteboard.clearContents()
    pasteboard.setData(tiff, forType: .tiff)
    monitor.checkForChanges()
    check(images.count == 1 && ImagePNG.isPNG(images[0]), "tiff pasteboard contents are stored as png")

    texts.removeAll()
    pasteboard.clearContents()
    pasteboard.setString("after-image", forType: .string)
    monitor.checkForChanges()
    check(texts == ["after-image"], "text copies still record after an image")

    images.removeAll()
    texts.removeAll()
    pasteboard.clearContents()
    let mixed = NSPasteboardItem()
    mixed.setData(png, forType: .png)
    mixed.setString("https://example.com/pic.png", forType: .string)
    pasteboard.writeObjects([mixed])
    monitor.checkForChanges()
    check(texts == ["https://example.com/pic.png"], "text alongside an image is kept")
    check(images.isEmpty, "a text copy is not replaced by its image preview")
    check(monitor.existingImagePNG() == nil, "image import skips pasteboards that also have text")
}

private func testScreenshotNamesAndNewFiles() {
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/Screenshot 2026.png"), dedicatedFolder: false),
        "english screenshot names are recognized"
    )
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/屏幕快照 2026.png"), dedicatedFolder: false),
        "chinese screenshot names are recognized"
    )
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/截屏2026.png"), dedicatedFolder: false),
        "截屏 names are recognized"
    )
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/vacation.png"), dedicatedFolder: false) == false,
        "other desktop images are ignored"
    )
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/vacation.jpg"), dedicatedFolder: true),
        "a dedicated screenshot folder accepts any image"
    )
    check(
        ScreenshotMonitor.isScreenshotFile(URL(fileURLWithPath: "/tmp/notes.txt"), dedicatedFolder: true) == false,
        "non-images are ignored"
    )

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let existing = solidPNG(width: 2, height: 2, red: 5)
    let captured = solidPNG(width: 2, height: 2, red: 6)
    let edited = solidPNG(width: 2, height: 2, red: 7)
    try! existing.write(to: directory.appendingPathComponent("Screenshot existing.png"))

    let monitor = ScreenshotMonitor(directory: directory, dedicatedFolder: false, interval: 60)
    var seen: [Data] = []
    monitor.onScreenshots = { batch in seen.append(contentsOf: batch.map(\.png)) }
    monitor.start()
    defer { monitor.stop() }
    monitor.checkForNewScreenshots()
    check(seen.isEmpty, "screenshots already in the folder are not copied")

    try! captured.write(to: directory.appendingPathComponent("vacation.png"))
    monitor.checkForNewScreenshots()
    monitor.checkForNewScreenshots()
    check(seen.isEmpty, "a new desktop image with another name is ignored")

    let shot = directory.appendingPathComponent("截屏2026-10-10.png")
    try! captured.write(to: shot)
    monitor.checkForNewScreenshots()
    check(seen.isEmpty, "a screenshot is copied only after the file stops growing")
    monitor.checkForNewScreenshots()
    check(seen == [captured], "a finished screenshot is reported")

    try! edited.write(to: shot)
    monitor.checkForNewScreenshots()
    monitor.checkForNewScreenshots()
    check(seen == [captured, edited], "a resaved screenshot is reported again")

    let older = solidPNG(width: 2, height: 2, red: 8)
    let newer = solidPNG(width: 2, height: 2, red: 9)
    var olderURL = directory.appendingPathComponent("Screenshot older.png")
    var newerURL = directory.appendingPathComponent("Screenshot newer.png")
    try! older.write(to: olderURL)
    try! newer.write(to: newerURL)
    var olderStamp = URLResourceValues()
    olderStamp.contentModificationDate = Date(timeIntervalSince1970: 10)
    var newerStamp = URLResourceValues()
    newerStamp.contentModificationDate = Date(timeIntervalSince1970: 20)
    try! olderURL.setResourceValues(olderStamp)
    try! newerURL.setResourceValues(newerStamp)
    var batches: [[CapturedShot]] = []
    monitor.pasteboardToken = { 4 }
    monitor.onScreenshots = { batches.append($0) }
    monitor.checkForNewScreenshots()
    monitor.checkForNewScreenshots()
    check(batches.count == 1, "screenshots found together arrive as one batch")
    check(batches.first?.map(\.png) == [older, newer], "the batch is oldest first")
    check(
        ScreenshotMonitor.clipboardImage(in: batches[0], pasteboardToken: 4) == newer,
        "the newest screenshot is the one copied"
    )
    check(
        ScreenshotMonitor.clipboardImage(in: batches[0], pasteboardToken: 9) == nil,
        "a newer clipboard copy is left alone"
    )
}

private func testOlderImageStaysBehindANewerCopy() {
    withStore { store in
        store.add("after", at: Date(timeIntervalSince1970: 200))
        store.addImage(solidPNG(width: 2, height: 2, red: 3), at: Date(timeIntervalSince1970: 100))
        check(store.items.map(\.isImage) == [false, true], "older image is not placed first")
        check(store.items[1].copiedAt == Date(timeIntervalSince1970: 100), "image keeps the file time")
    }
}

private func testReencodedImageDoesNotDuplicate() {
    withStore { store in
        let png = solidPNG(width: 2, height: 2, red: 15)
        let tiff = ImagePNG.tiffRepresentation(ofPNG: png)!
        let again = ImagePNG.normalizedPNG(tiff)!
        check(store.addImage(png), "original png is stored")
        check(store.addImage(again), "reencoded png is accepted")
        check(store.items.count == 1, "same pixels are one history row")
    }
}

private func testImageSearchSelectsTheMatchingPicture() {
    withStore { store in
        store.add("会议记录", at: Date(timeIntervalSince1970: 1_700_000_000))
        store.addImage(solidPNG(width: 8, height: 5, red: 12), at: Date(timeIntervalSince1970: 1_700_000_100))
        let model = HistoryModel()
        model.prepare(store.items)

        check(model.selectedItem?.isImage == true, "the newest image is selected when the panel opens")
        model.query = "图片"
        check(model.filtered.count == 1 && model.filtered[0].isImage, "searching 图片 keeps image rows")
        check(model.selectedItem?.text == "图片\n8×5", "search selects that image")
        model.query = "会议"
        check(model.filtered.map(\.text) == ["会议记录"], "text search still ignores images")
    }
}

private func testSpaceTogglesPreviewOfTheSelectedCopy() {
    withStore { store in
        store.add("第一行\n更多内容", at: Date(timeIntervalSince1970: 1_700_000_000))
        let model = HistoryModel()
        model.prepare(store.items)

        check(model.isPreviewing == false, "preview starts closed")
        model.togglePreview()
        check(model.isPreviewing, "space opens the preview")
        check(model.selectedItem?.text == "第一行\n更多内容", "preview uses the selected copy")
        model.togglePreview()
        check(model.isPreviewing == false, "space closes the preview")

        model.togglePreview()
        model.prepare(store.items)
        check(model.isPreviewing == false, "opening the panel closes the preview")

        model.prepare([])
        model.togglePreview()
        check(model.isPreviewing == false, "space does nothing without a selection")
    }
}

private func testPinSurvivesReloadAndIsKeptPastTheCap() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PastyTests-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("history.json")
    let store = ClipboardStore(fileURL: fileURL)
    let pinnedDate = Date(timeIntervalSince1970: 1_700_000_000)
    store.add("keep", at: pinnedDate)
    let pinnedID = store.items[0].id
    check(store.setPinned(id: pinnedID, pinned: true), "a card can be pinned")
    store.add("keep", at: Date(timeIntervalSince1970: 1_700_000_050))
    check(store.items.first?.pinned == true, "copying the same text keeps the pin")
    check(store.items.filter { $0.text == "keep" }.count == 1, "a pinned copy is not duplicated")

    for index in 0..<120 {
        store.add("item-\(index)", at: Date(timeIntervalSince1970: TimeInterval(1_700_000_100 + index)))
    }
    check(store.items.contains { $0.id == pinnedID && $0.pinned }, "pinned cards are not trimmed")
    check(store.items.filter { !$0.pinned }.count == ClipboardStore.maxItems, "unpinned history stays at 100")

    let reloaded = ClipboardStore(fileURL: fileURL)
    check(reloaded.items.contains { $0.id == pinnedID && $0.pinned }, "pins survive a reload")
    check(reloaded.setPinned(id: UUID(), pinned: true) == false, "unknown cards are not pinned")
}

private func testPinnedShelfShowsOnlyPinnedCards() {
    withStore { store in
        store.add("older", at: Date(timeIntervalSince1970: 1_700_000_000))
        store.add("middle", at: Date(timeIntervalSince1970: 1_700_000_100))
        store.add("newer", at: Date(timeIntervalSince1970: 1_700_000_200))
        let middle = store.items[1]
        store.setPinned(id: middle.id, pinned: true)

        let model = HistoryModel()
        model.prepare(store.items)
        check(model.shelf == .recent, "the panel opens on recent cards")
        check(model.filtered.count == 3, "recent shelf shows every card")
        check(model.pinnedCount == 1, "one card is pinned")

        model.showPinned()
        check(model.filtered.map(\.text) == ["middle"], "pinned shelf shows only pinned cards")
        check(model.selectedText() == "middle", "opening the pinned shelf selects that card")

        model.applyPin(id: middle.id, pinned: false)
        check(model.filtered.isEmpty, "unpinning the last card clears the pinned shelf")
        check(model.selectedText() == nil, "an empty pinned shelf has nothing selected")

        model.showRecent()
        check(model.filtered.count == 3, "recent shelf still has the unpinned card")
    }
}

testAddPlacesNewestFirstAndSkipsBlankText()
testDuplicateTextMovesExistingItemToFront()
testItemsAreCappedAtOneHundred()
testDuplicateAtCapacityDoesNotDropOtherItems()
testHistoryRoundTripsThroughJSON()
testClearRemovesPersistedHistory()
testDeleteRemovesOneItemAndItsImage()
testRemovingTheSelectionMovesToTheNextRow()
testBlankTextDoesNotEraseExistingHistory()
testMonitorRecordsExternalCopiesAndSkipsItsOwnWrite()
testMonitorSkipsBlankAndConcealedContents()
testSelectionMovesAndSearchFilters()
testLegacyHistoryWithoutImageFieldsStillLoads()
testImagesAreStoredDedupedAndRemovedWithHistory()
testImageHistoryDropsTheOldestFileAtCapacity()
testMonitorRecordsImagesAndSkipsItsOwnWrite()
testScreenshotNamesAndNewFiles()
testOlderImageStaysBehindANewerCopy()
testReencodedImageDoesNotDuplicate()
testImageSearchSelectsTheMatchingPicture()
testSpaceTogglesPreviewOfTheSelectedCopy()
testPinSurvivesReloadAndIsKeptPastTheCap()
testPinnedShelfShowsOnlyPinnedCards()

if failures > 0 {
    fputs("\(failures) test(s) failed\n", stderr)
    exit(1)
}
print("All tests passed")
