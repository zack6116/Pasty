import AppKit
import ImageIO
import PastyCore
import SwiftUI

enum PastePalette {
    static let paper = Color(red: 0.965, green: 0.941, blue: 0.898)
    static let paperDeep = Color(red: 0.925, green: 0.886, blue: 0.824)
    static let card = Color(red: 1.0, green: 0.988, blue: 0.973)
    static let ink = Color(red: 0.110, green: 0.094, blue: 0.078)
    static let muted = Color(red: 0.541, green: 0.506, blue: 0.459)
    static let line = Color(red: 0.878, green: 0.824, blue: 0.745)
    static let copper = Color(red: 0.769, green: 0.318, blue: 0.173)
    static let moss = Color(red: 0.122, green: 0.420, blue: 0.290)
    static let mossWash = Color(red: 0.886, green: 0.941, blue: 0.906)
}

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    var imageURL: (ClipItem) -> URL?
    var onCopy: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void
    var onPin: (ClipItem) -> Void

    @FocusState private var searchFocused: Bool
    @State private var hoveredID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: HistoryPanelMetrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HistoryPanelMetrics.cornerRadius, style: .continuous)
                .strokeBorder(PastePalette.line, lineWidth: 1)
        )
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { _ in
            searchFocused = true
        }
        .onChange(of: model.query) { _ in
            if model.isPreviewing {
                model.closePreview()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: model.isPreviewing)
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: [PastePalette.paper, PastePalette.paperDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PastePalette.copper)
                Text("剪贴板")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PastePalette.ink)
            }
            shelfSwitch
            Spacer(minLength: 8)
            Text("\(model.filtered.count)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(PastePalette.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.55)))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var shelfSwitch: some View {
        HStack(spacing: 2) {
            shelfButton("最近", selected: model.shelf == .recent) {
                model.showRecent()
            }
            shelfButton("固定 \(model.pinnedCount)", selected: model.shelf == .pinned) {
                model.showPinned()
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.45)))
    }

    private func shelfButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : PastePalette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(selected ? PastePalette.ink : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(PastePalette.muted)
            TextField("搜索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(PastePalette.ink)
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(PastePalette.line, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if model.items.isEmpty {
                emptyLabel(symbol: "doc.on.clipboard", title: "暂无复制记录")
            } else if model.shelf == .pinned && model.pinnedCount == 0 && model.query.isEmpty {
                emptyLabel(symbol: "pin", title: "还没有固定的卡片")
            } else if model.filtered.isEmpty {
                emptyLabel(symbol: "magnifyingglass", title: "没有匹配的记录")
            } else {
                cardStrip
            }
            if model.isPreviewing, let item = model.selectedItem {
                preview(item)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
            }
        }
    }

    private var cardStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(model.filtered) { item in
                        card(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .onChange(of: model.selectedID) { id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func card(_ item: ClipItem) -> some View {
        let parts = Self.parts(of: item.text)
        let selected = item.id == model.selectedID
        let hovered = hoveredID == item.id
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                if item.isImage, let url = imageURL(item) {
                    ClipThumbnail(url: url, maxPixel: 360)
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .background(PastePalette.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text(parts.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(PastePalette.ink)
                    .lineLimit(item.isImage ? 1 : 4)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                HStack(spacing: 6) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PastePalette.copper)
                    }
                    Text(Self.relativeFormatter.localizedString(for: item.copiedAt, relativeTo: Date()))
                        .font(.system(size: 11))
                        .foregroundStyle(PastePalette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .padding(.trailing, 18)
            .frame(width: 196, height: 176, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? PastePalette.mossWash : PastePalette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? PastePalette.moss : (hovered ? PastePalette.copper.opacity(0.55) : PastePalette.line),
                        lineWidth: selected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture {
                model.select(item.id)
                onCopy(item)
            }

            Button {
                onPin(item)
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.pinned ? PastePalette.copper : PastePalette.muted)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(item.pinned ? PastePalette.copper.opacity(0.16) : Color.white.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "取消固定" : "固定")
            .padding(8)
        }
        .contextMenu {
            Button(item.pinned ? "取消固定" : "固定") {
                onPin(item)
            }
            Button("删除") {
                onDelete(item)
            }
        }
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
    }

    private func preview(_ item: ClipItem) -> some View {
        ZStack {
            Color.black.opacity(0.28)
                .contentShape(Rectangle())
                .onTapGesture { model.closePreview() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: item.isImage ? "photo" : "plus.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PastePalette.muted)
                    Text("预览")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PastePalette.ink)
                    Spacer()
                    Text(item.isImage ? (Self.parts(of: item.text).detail ?? "图片") : "\(item.text.count) 个字符")
                        .font(.system(size: 11))
                        .foregroundStyle(PastePalette.muted)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider().opacity(0.5)

                if item.isImage, let url = imageURL(item) {
                    ClipThumbnail(url: url, maxPixel: 1600, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 360)
                        .padding(18)
                } else {
                    ViewThatFits(in: .vertical) {
                        Text(Self.previewBody(item.text))
                            .font(.system(size: 17))
                            .lineSpacing(6)
                            .foregroundStyle(PastePalette.ink)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(18)
                        ScrollView {
                            Text(Self.previewBody(item.text))
                                .font(.system(size: 17))
                                .lineSpacing(6)
                                .foregroundStyle(PastePalette.ink)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .textSelection(.enabled)
                                .padding(18)
                        }
                        .frame(height: 460)
                    }
                }

                Divider().opacity(0.5)
                Text("空格或 esc 关闭")
                    .font(.system(size: 11))
                    .foregroundStyle(PastePalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .background(PastePalette.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(PastePalette.line, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
            .padding(16)
        }
    }

    private func emptyLabel(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(PastePalette.copper)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(PastePalette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            keyHint("←→", "选择")
            keyHint("空格", "预览")
            keyHint("↩", "复制")
            keyHint("⌘P", "固定")
            keyHint("⌘2", "只看固定")
            keyHint("esc", "关闭")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(PastePalette.paperDeep.opacity(0.65))
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(PastePalette.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.7))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(PastePalette.muted)
        }
    }

    private static func parts(of text: String) -> (title: String, detail: String?) {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let title = String((lines.first ?? text).prefix(240))
        let detail = lines.dropFirst().first.map { String($0.prefix(240)) }
        return (title, detail)
    }

    private static func previewBody(_ text: String) -> String {
        guard text.count > 12_000 else { return text }
        return String(text.prefix(12_000)) + "\n\n…"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter
    }()
}

private struct ClipThumbnail: View {
    let url: URL
    let maxPixel: CGFloat
    var contentMode: ContentMode = .fill
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(PastePalette.muted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear { load() }
        .onChange(of: url) { _ in load() }
    }

    private func load() {
        image = ThumbnailCache.shared.image(at: url, maxPixel: maxPixel)
    }
}

private final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(at url: URL, maxPixel: CGFloat) -> NSImage? {
        let key = "\(url.path)|\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
