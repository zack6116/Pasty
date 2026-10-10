import Foundation

public struct ClipItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var text: String
    public var copiedAt: Date

    public init(id: UUID, text: String, copiedAt: Date) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
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

        if let index = items.firstIndex(where: { $0.text == text }) {
            var existing = items.remove(at: index)
            existing.copiedAt = date
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(id: UUID(), text: text, copiedAt: date), at: 0)
            if items.count > Self.maxItems {
                items.removeLast(items.count - Self.maxItems)
            }
        }
        save()
        return true
    }

    public func contains(_ text: String) -> Bool {
        items.contains(where: { $0.text == text })
    }

    public func clear() {
        items.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? decoder.decode([ClipItem].self, from: data) else { return }
        items = Array(decoded.prefix(Self.maxItems))
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
}
