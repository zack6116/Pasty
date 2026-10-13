import CryptoKit
import Foundation

public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var copiedAt: Date
    public var imageFile: String?
    public var contentHash: String?
    public var pinned: Bool
    public var boardID: UUID?

    public var isImage: Bool { imageFile != nil }

    public init(
        id: UUID,
        text: String,
        copiedAt: Date,
        imageFile: String? = nil,
        contentHash: String? = nil,
        pinned: Bool = false,
        boardID: UUID? = nil
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.imageFile = imageFile
        self.contentHash = contentHash
        self.pinned = pinned
        self.boardID = boardID
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, copiedAt, imageFile, contentHash, pinned, boardID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        copiedAt = try container.decode(Date.self, forKey: .copiedAt)
        imageFile = try container.decodeIfPresent(String.self, forKey: .imageFile)
        contentHash = try container.decodeIfPresent(String.self, forKey: .contentHash)
        pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        boardID = try container.decodeIfPresent(UUID.self, forKey: .boardID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(copiedAt, forKey: .copiedAt)
        try container.encodeIfPresent(imageFile, forKey: .imageFile)
        try container.encodeIfPresent(contentHash, forKey: .contentHash)
        try container.encode(pinned, forKey: .pinned)
        try container.encodeIfPresent(boardID, forKey: .boardID)
    }
}

public struct PinBoard: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

public final class ClipboardStore {
    public static let maxItems = 100
    public static let maxBoards = 12
    public static let maxBoardNameLength = 16
    public static let defaultBoardName = "固定"

    public private(set) var items: [ClipItem] = []
    public private(set) var boards: [PinBoard] = []

    private let fileURL: URL
    private let boardsURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
        boardsURL = fileURL.deletingLastPathComponent().appendingPathComponent("boards.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        load()
    }

    @discardableResult
    public func add(_ text: String, at date: Date = Date()) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        if let index = items.firstIndex(where: { $0.imageFile == nil && $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(id: UUID(), text: text, copiedAt: date), at: 0)
            trimToCapacity()
        }
        save()
        return true
    }

    /// Stores a PNG and moves an identical image to the front instead of duplicating it.
    @discardableResult
    public func addImage(_ pngData: Data, at date: Date = Date()) -> Bool {
        guard ImagePNG.isPNG(pngData) else { return false }
        let hash = Self.digest(pngData)

        if let index = items.firstIndex(where: { $0.contentHash == hash && $0.imageFile != nil }) {
            var existing = items.remove(at: index)
            let previousDate = existing.copiedAt
            existing.copiedAt = date
            if let imageFile = existing.imageFile, !fileExists(imageFile) {
                guard writeImage(pngData, named: imageFile) else {
                    existing.copiedAt = previousDate
                    items.insert(existing, at: index)
                    return false
                }
            }
            insertChronologically(existing)
            save()
            return true
        }

        let id = UUID()
        let filename = "\(id.uuidString).png"
        guard writeImage(pngData, named: filename) else { return false }
        let label = ImagePNG.pixelLabel(ofPNG: pngData).map { "图片\n\($0)" } ?? "图片"
        insertChronologically(
            ClipItem(id: id, text: label, copiedAt: date, imageFile: filename, contentHash: hash)
        )
        trimToCapacity()
        save()
        return true
    }

    public func contains(_ text: String) -> Bool {
        items.contains(where: { $0.imageFile == nil && $0.text == text })
    }

    public func containsImage(_ pngData: Data) -> Bool {
        guard ImagePNG.isPNG(pngData) else { return false }
        let hash = Self.digest(pngData)
        return items.contains(where: { $0.contentHash == hash && $0.imageFile != nil })
    }

    public func imageURL(for item: ClipItem) -> URL? {
        guard let imageFile = item.imageFile else { return nil }
        let url = imagesDirectory.appendingPathComponent(imageFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func imageData(for item: ClipItem) -> Data? {
        guard let url = imageURL(for: item) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Keeps a clip out of the 100-item trim. Unpinning can drop it if history is already full.
    /// Pinning with no named board yet creates the default board.
    @discardableResult
    public func setPinned(id: UUID, pinned: Bool) -> Bool {
        if pinned {
            let board = boards.first ?? addBoard(name: Self.defaultBoardName)
            guard let board else { return false }
            return assign(id: id, boardID: board.id)
        }
        return assign(id: id, boardID: nil)
    }

    @discardableResult
    public func addBoard(name: String) -> PinBoard? {
        let trimmed = Self.sanitizeBoardName(name)
        guard !trimmed.isEmpty, boards.count < Self.maxBoards else { return nil }
        guard !boards.contains(where: { $0.name == trimmed }) else { return nil }
        let board = PinBoard(name: trimmed)
        boards.append(board)
        saveBoards()
        return board
    }

    @discardableResult
    public func renameBoard(id: UUID, name: String) -> Bool {
        guard let index = boards.firstIndex(where: { $0.id == id }) else { return false }
        let trimmed = Self.sanitizeBoardName(name)
        guard !trimmed.isEmpty else { return false }
        guard !boards.contains(where: { $0.id != id && $0.name == trimmed }) else { return false }
        boards[index].name = trimmed
        saveBoards()
        return true
    }

    /// Removes the board and returns its cards to ordinary history, where the 100-item cap applies again.
    @discardableResult
    public func deleteBoard(id: UUID) -> Bool {
        guard boards.contains(where: { $0.id == id }) else { return false }
        boards.removeAll { $0.id == id }
        for index in items.indices where items[index].boardID == id {
            items[index].boardID = nil
            items[index].pinned = false
        }
        trimToCapacity()
        saveBoards()
        save()
        return true
    }

    @discardableResult
    public func assign(id: UUID, boardID: UUID?) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        if let boardID, !boards.contains(where: { $0.id == boardID }) { return false }
        items[index].boardID = boardID
        items[index].pinned = boardID != nil
        if boardID == nil {
            trimToCapacity()
        }
        save()
        return true
    }

    @discardableResult
    public func delete(id: UUID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        let removed = items.remove(at: index)
        deleteImageFile(removed.imageFile)
        save()
        return true
    }

    public func clear() {
        let removed = items
        items.removeAll()
        removed.forEach { deleteImageFile($0.imageFile) }
        save()
    }

    private func load() {
        boards = loadBoards()
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard var decoded = try? decoder.decode([ClipItem].self, from: data) else { return }
        let migrated = attachLegacyPins(&decoded)
        var unpinnedKept = 0
        var kept: [ClipItem] = []
        kept.reserveCapacity(min(decoded.count, Self.maxItems))
        for item in decoded {
            if item.pinned {
                kept.append(item)
            } else if unpinnedKept < Self.maxItems {
                unpinnedKept += 1
                kept.append(item)
            }
        }
        let available = kept.filter { item in
            guard let imageFile = item.imageFile else { return true }
            return fileExists(imageFile)
        }
        items = available
        if migrated || available.count != decoded.count {
            save()
        }
    }

    /// Older history used a single pin flag. Those cards move onto the first board.
    private func attachLegacyPins(_ decoded: inout [ClipItem]) -> Bool {
        let needsFallback = decoded.contains { $0.pinned && $0.boardID == nil }
        if needsFallback && boards.isEmpty {
            boards = [PinBoard(name: Self.defaultBoardName)]
            saveBoards()
        }
        let fallback = boards.first?.id
        var changed = false
        for index in decoded.indices {
            if decoded[index].pinned && decoded[index].boardID == nil {
                decoded[index].boardID = fallback
                changed = true
            }
            if let boardID = decoded[index].boardID, !boards.contains(where: { $0.id == boardID }) {
                decoded[index].boardID = nil
                changed = true
            }
            let pinned = decoded[index].boardID != nil
            if decoded[index].pinned != pinned {
                decoded[index].pinned = pinned
                changed = true
            }
        }
        return changed
    }

    private func loadBoards() -> [PinBoard] {
        guard let data = try? Data(contentsOf: boardsURL),
              let decoded = try? decoder.decode([PinBoard].self, from: data) else {
            return []
        }
        var seen = Set<String>()
        return decoded.prefix(Self.maxBoards).compactMap { board in
            let name = Self.sanitizeBoardName(board.name)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return PinBoard(id: board.id, name: name)
        }
    }

    private func saveBoards() {
        do {
            let directory = boardsURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(boards)
            try data.write(to: boardsURL, options: .atomic)
        } catch {
            fputs("Pasty failed to save boards: \(error)\n", stderr)
        }
    }

    private static func sanitizeBoardName(_ name: String) -> String {
        let trimmed = name
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxBoardNameLength))
    }

    private func save() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("Pasty failed to save history: \(error)\n", stderr)
        }
    }

    private var imagesDirectory: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("images", isDirectory: true)
    }

    private func insertChronologically(_ item: ClipItem) {
        let index = items.firstIndex(where: { $0.copiedAt <= item.copiedAt }) ?? items.count
        items.insert(item, at: index)
    }

    /// The cap applies to unpinned history. Pinned cards stay until they are unpinned or deleted.
    private func trimToCapacity() {
        while items.filter({ !$0.pinned }).count > Self.maxItems {
            guard let index = items.lastIndex(where: { !$0.pinned }) else { return }
            let dropped = items.remove(at: index)
            deleteImageFile(dropped.imageFile)
        }
    }

    private func writeImage(_ data: Data, named filename: String) -> Bool {
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            try data.write(to: imagesDirectory.appendingPathComponent(filename), options: .atomic)
            return true
        } catch {
            fputs("Pasty failed to save image: \(error)\n", stderr)
            return false
        }
    }

    private func fileExists(_ filename: String?) -> Bool {
        guard let filename else { return false }
        return FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(filename).path)
    }

    private func deleteImageFile(_ filename: String?) {
        guard let filename else { return }
        try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(filename))
    }

    private static func digest(_ data: Data) -> String {
        if let fingerprint = ImagePNG.pixelFingerprint(data) {
            return fingerprint
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
