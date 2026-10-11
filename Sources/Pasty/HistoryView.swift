import AppKit
import ImageIO
import PastyCore
import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    var imageURL: (ClipItem) -> URL?
    var onCopy: (ClipItem) -> Void
    var onDelete: (ClipItem) -> Void

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
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8)
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
        ZStack {
            RoundedRectangle(cornerRadius: HistoryPanelMetrics.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            LinearGradient(
                colors: [Color.white.opacity(0.16), Color.white.opacity(0.03)],
                startPoint: .top,
                endPoint: .center
            )
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("剪贴板")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text("\(model.filtered.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            Color.primary.opacity(0.025)
            if model.items.isEmpty {
                emptyLabel(symbol: "doc.on.clipboard", title: "暂无复制记录")
            } else if model.filtered.isEmpty {
                emptyLabel(symbol: "magnifyingglass", title: "没有匹配的记录")
            } else {
                list
            }
            if model.isPreviewing, let item = model.selectedItem {
                preview(item)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .center)))
            }
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(model.filtered) { item in
                        row(item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .onChange(of: model.selectedID) { id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func row(_ item: ClipItem) -> some View {
        let parts = Self.parts(of: item.text)
        let selected = item.id == model.selectedID
        return Button {
            model.select(item.id)
            onCopy(item)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if item.isImage, let url = imageURL(item) {
                    ClipThumbnail(url: url, maxPixel: 120)
                        .frame(width: 52, height: 40)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(parts.detail == nil ? 2 : 1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                    if let detail = parts.detail {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 8)
                Text(Self.relativeFormatter.localizedString(for: item.copiedAt, relativeTo: Date()))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(selected: selected, hovered: hoveredID == item.id))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除") {
                onDelete(item)
            }
        }
        .onHover { hovering in
            hoveredID = hovering ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
    }

    private func rowBackground(selected: Bool, hovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                selected
                    ? Color.accentColor.opacity(0.18)
                    : Color.primary.opacity(hovered ? 0.06 : 0.0)
            )
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
                        .foregroundStyle(.secondary)
                    Text("预览")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(item.isImage ? (Self.parts(of: item.text).detail ?? "图片") : "\(item.text.count) 个字符")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
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
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(18)
                        ScrollView {
                            Text(Self.previewBody(item.text))
                                .font(.system(size: 17))
                                .lineSpacing(6)
                                .foregroundStyle(.primary)
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
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 28, y: 12)
            .padding(16)
        }
    }

    private func emptyLabel(symbol: String, title: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            keyHint("↑↓", "选择")
            keyHint("空格", "预览")
            keyHint("↩", "复制")
            keyHint("右键", "删除")
            keyHint("esc", "关闭")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.03))
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
