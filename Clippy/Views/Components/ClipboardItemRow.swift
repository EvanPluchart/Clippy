import AppKit
import SwiftUI

struct ClipboardItemRow: View {
    @EnvironmentObject private var state: AppState
    let item: ClipboardItem
    var compact = false
    var shortcutLabel: String?
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 10 : 12) {
            visual
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: item.type.symbol).foregroundStyle(.secondary)
                    Text(item.type.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    if item.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.orange) }
                    Spacer()
                    if let shortcutLabel {
                        Text(shortcutLabel)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(
                        item.lastUsedAt.formatted(
                            .relative(presentation: .named, unitsStyle: .abbreviated)
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                Text(item.preview.isEmpty ? String(localized: "Sans aperçu") : item.preview)
                    .font(compact ? .callout : .body)
                    .lineLimit(compact ? 2 : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.disabled)
                HStack {
                    Text(metadata).font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    if let source = item.sourceApplication {
                        Text(source)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(compact ? 10 : 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.type.title), \(item.preview)")
        .accessibilityValue(metadata)
        .contextMenu {
            Button("Copier") { state.copy(item) }
            if item.content != nil {
                Button("Copier en texte brut") { state.copy(item, plainTextOnly: true) }
            }
            Button(
                item.isPinned ? String(localized: "Désépingler") : String(localized: "Épingler")
            ) {
                state.repository.togglePinned(item)
            }
            Divider()
            if item.type == .image, let path = item.relativeFilePath {
                Button("Afficher en grand") {
                    Task {
                        if let url = await state.fileStorage.absoluteURL(relativePath: path) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            if item.type == .url, let value = item.content, let url = URL(string: value) {
                Button("Ouvrir le lien") { NSWorkspace.shared.open(url) }
            }
            if item.type == .file,
               let content = item.content,
               let path = ClipboardFileList.paths(from: content).first {
                Button("Révéler dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                }
            }
            Button("Supprimer", role: .destructive) { state.delete([item]) }
        }
        .task(id: item.relativeThumbnailPath) {
            guard let path = item.relativeThumbnailPath else {
                thumbnail = nil
                return
            }
            thumbnail = await state.thumbnailCache.image(relativePath: path, storage: state.fileStorage)
        }
    }

    @ViewBuilder private var visual: some View {
        if item.type == .image {
            Group {
                if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFill() }
                else { Image(systemName: "photo").font(.title2).foregroundStyle(.secondary) }
            }
            .frame(width: compact ? 54 : 72, height: compact ? 54 : 72)
            .background(.quaternary)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if item.type == .color {
            RoundedRectangle(cornerRadius: 9).fill(Color(hex: item.content ?? "") ?? .secondary)
                .frame(width: compact ? 46 : 56, height: compact ? 46 : 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(.primary.opacity(0.12), lineWidth: 1)
                }
        } else {
            Image(systemName: item.type.symbol)
                .font(compact ? .title3 : .title2)
                .foregroundStyle(.secondary)
                .frame(width: compact ? 42 : 52, height: compact ? 42 : 52)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var metadata: String {
        switch item.type {
        case .image:
            let dimensions = item.imageWidth.flatMap { w in item.imageHeight.map { "\(w) × \($0) · " } } ?? ""
            return dimensions + item.estimatedSize.formattedBytes
        case .plainText, .richText:
            return L10n.textUsage(
                characterCount: item.content?.count ?? 0,
                useCount: item.useCount
            )
        default: return item.estimatedSize.formattedBytes
        }
    }
}

private extension Color {
    init?(hex: String) {
        let original = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let usesARGB = original.hasPrefix("0X") && original.count == 10
        var value = original
        if value.hasPrefix("#") { value.removeFirst() }
        if value.hasPrefix("0X") { value.removeFirst(2) }
        if value.count == 3 || value.count == 4 {
            value = value.map { "\($0)\($0)" }.joined()
        }
        guard (value.count == 6 || value.count == 8),
              let number = UInt64(value, radix: 16) else {
            return nil
        }
        let hasAlpha = value.count == 8
        let redShift: UInt64 = usesARGB ? 16 : (hasAlpha ? 24 : 16)
        let greenShift: UInt64 = usesARGB ? 8 : (hasAlpha ? 16 : 8)
        let blueShift: UInt64 = usesARGB ? 0 : (hasAlpha ? 8 : 0)
        let alphaValue = usesARGB ? (number >> 24) & 255 : number & 255
        let alpha = hasAlpha ? Double(alphaValue) / 255 : 1
        self.init(
            red: Double((number >> redShift) & 255) / 255,
            green: Double((number >> greenShift) & 255) / 255,
            blue: Double((number >> blueShift) & 255) / 255,
            opacity: alpha
        )
    }
}

struct TypeFilterBar: View {
    @Binding var selection: ClipboardItemType?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            buttons(showTitles: true)
            buttons(showTitles: false)
            ScrollView(.horizontal, showsIndicators: false) {
                buttons(showTitles: true)
            }
        }
    }

    private func buttons(showTitles: Bool) -> some View {
        HStack(spacing: 7) {
            filterButton(
                nil,
                title: String(localized: "Tout"),
                symbol: "square.grid.2x2",
                showTitle: showTitles
            )
            ForEach(ClipboardItemType.allCases.filter { $0 != .unknown }) { type in
                filterButton(type, title: type.title, symbol: type.symbol, showTitle: showTitles)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func filterButton(
        _ type: ClipboardItemType?,
        title: String,
        symbol: String,
        showTitle: Bool
    ) -> some View {
        Button {
            selection = type
        } label: {
            if showTitle {
                Label(title, systemImage: symbol)
            } else {
                Image(systemName: symbol)
                    .accessibilityLabel(title)
                    .frame(width: 18)
            }
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .contentShape(Capsule())
        .buttonStyle(.plain)
        .background(
            selection == type ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.09),
            in: Capsule()
        )
        .accessibilityAddTraits(selection == type ? .isSelected : [])
    }
}
