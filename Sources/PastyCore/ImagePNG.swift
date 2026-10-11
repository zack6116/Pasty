import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public enum ImagePNG {
    public static func isPNG(_ data: Data) -> Bool {
        data.count >= 24 && data.prefix(8).elementsEqual(signature)
    }

    /// PNG bytes ready to store. An already-decodable PNG is returned unchanged.
    public static func normalizedPNG(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        if isPNG(data), canDecode(data) {
            return data
        }
        return reencodedPNG(data)
    }

    public static func pixelLabel(ofPNG data: Data) -> String? {
        guard isPNG(data), let width = bigEndianUInt32(data, 16), let height = bigEndianUInt32(data, 20) else {
            return nil
        }
        guard width > 0, height > 0 else { return nil }
        return "\(width)×\(height)"
    }

    public static func tiffRepresentation(ofPNG data: Data) -> Data? {
        NSImage(data: data)?.tiffRepresentation
    }

    /// Stable across PNG and TIFF encodings of the same pixels.
    public static func pixelFingerprint(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width <= 20_000, height <= 20_000 else { return nil }
        let bytesPerRow = width * 4
        let count = height * bytesPerRow
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: count)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let digest = SHA256.hash(data: Data(bytes: buffer, count: count))
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(width)x\(height):\(digest)"
    }

    private static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static func canDecode(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0 && CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }

    private static func reencodedPNG(_ data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              isPNG(png),
              canDecode(png) else {
            return nil
        }
        return png
    }

    private static func bigEndianUInt32(_ data: Data, _ offset: Int) -> UInt32? {
        guard data.count >= offset + 4 else { return nil }
        return data[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
