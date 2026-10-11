import CryptoKit
import Foundation

public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var copiedAt: Date
    public var imageFile: String?
    public var contentHash: String?

    public var isImage: Bool { imageFile != nil }

    public init(
        id: UUID,
        text: String,
        copiedAt: Date,
        imageFile: String? = nil,
        contentHash: String? = nil
    ) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
        self.imageFile = imageFile
        self.contentHash = contentHash
    }
}

public final class ClipboardStore {
    public static let maxItems = 100

    public private(set) var items: [ClipItem] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL
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
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? decoder.decode([ClipItem].self, from: data) else { return }
        let capped = Array(decoded.prefix(Self.maxItems))
        let available = capped.filter { item in
            guard let imageFile = item.imageFile else { return true }
            return fileExists(imageFile)
        }
        items = available
        if available.count != capped.count {
            save()
        }
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

    private func trimToCapacity() {
        while items.count > Self.maxItems {
            let dropped = items.removeLast()
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
