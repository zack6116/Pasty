import Foundation

public struct CapturedShot: Equatable {
    public var png: Data
    public var modifiedAt: Date
    public var pasteboardToken: Int
}

/// Watches the macOS screenshot folder and reports images saved after it starts.
public final class ScreenshotMonitor {
    public var onScreenshots: (([CapturedShot]) -> Void)?
    /// Sampled when a file's size and mtime first settle, so a later copy is not overwritten.
    public var pasteboardToken: (() -> Int)?

    private let directory: URL
    private let dedicatedFolder: Bool
    private let interval: TimeInterval
    private var timer: Timer?
    private var knownStamps: [String: FileStamp] = [:]
    private var pending: [String: PendingFile] = [:]
    private var didReportAccessFailure = false

    private struct FileStamp: Equatable {
        var size: Int
        var modifiedAt: Date
    }

    private struct PendingFile {
        var stamp: FileStamp
        var token: Int
    }

    public init(directory: URL, dedicatedFolder: Bool, interval: TimeInterval = 0.4) {
        self.directory = directory
        self.dedicatedFolder = dedicatedFolder
        self.interval = interval
    }

    public static func resolvedLocation() -> (directory: URL, dedicatedFolder: Bool) {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true)
        let configured = CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String
        let directory = configured
            .map { ($0 as NSString).expandingTildeInPath }
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? desktop
        let dedicatedFolder = directory.standardizedFileURL.path != desktop.standardizedFileURL.path
        return (directory, dedicatedFolder)
    }

    public func start() {
        knownStamps = Dictionary(uniqueKeysWithValues: currentFiles().compactMap { url in
            stamp(of: url).map { (url.path, $0) }
        })
        pending = [:]
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForNewScreenshots()
        }
        timer.tolerance = interval / 2
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads the folder immediately. The running timer calls this on its own.
    public func checkForNewScreenshots() {
        var ready: [(path: String, stamp: FileStamp, shot: CapturedShot)] = []
        for url in currentFiles() {
            let path = url.path
            guard let stamp = stamp(of: url) else { continue }
            if knownStamps[path] == stamp {
                continue
            }
            guard let waiting = pending[path], waiting.stamp == stamp else {
                pending[path] = PendingFile(stamp: stamp, token: pasteboardToken?() ?? 0)
                continue
            }
            guard let data = try? Data(contentsOf: url), let png = ImagePNG.normalizedPNG(data) else {
                continue
            }
            ready.append((
                path,
                stamp,
                CapturedShot(png: png, modifiedAt: stamp.modifiedAt, pasteboardToken: waiting.token)
            ))
        }
        guard !ready.isEmpty else { return }
        ready.sort { $0.shot.modifiedAt < $1.shot.modifiedAt }
        for item in ready {
            knownStamps[item.path] = item.stamp
            pending[item.path] = nil
        }
        onScreenshots?(ready.map(\.shot))
    }

    /// The newest shot from one scan, when the pasteboard has not changed since that file settled.
    public static func clipboardImage(in batch: [CapturedShot], pasteboardToken: Int) -> Data? {
        guard let newest = batch.max(by: { $0.modifiedAt < $1.modifiedAt }),
              newest.pasteboardToken == pasteboardToken else { return nil }
        return newest.png
    }

    public static func isScreenshotFile(_ url: URL, dedicatedFolder: Bool) -> Bool {
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return false }
        if dedicatedFolder { return true }
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return namePrefixes.contains { name.hasPrefix($0) }
    }

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "heic", "gif"]
    private static let namePrefixes = ["screenshot", "screen shot", "屏幕快照", "屏幕截图", "截屏", "截图"]

    private func currentFiles() -> [URL] {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            return urls.filter { Self.isScreenshotFile($0, dedicatedFolder: dedicatedFolder) }
        } catch {
            if !didReportAccessFailure {
                didReportAccessFailure = true
                fputs("Pasty cannot read screenshots in \(directory.path): \(error)\n", stderr)
            }
            return []
        }
    }

    private func stamp(of url: URL) -> FileStamp? {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .isRegularFileKey,
        ])
        if values?.isRegularFile == false { return nil }
        guard let size = values?.fileSize, size > 0 else { return nil }
        return FileStamp(size: size, modifiedAt: values?.contentModificationDate ?? .distantPast)
    }
}
