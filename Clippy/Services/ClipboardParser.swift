import AppKit
import UniformTypeIdentifiers

enum ClipboardParser {
    static let maximumTextBytes = 5 * 1_048_576

    private static let transientTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("com.agilebits.onepassword")
    ]

    @MainActor
    static func parse(
        _ pasteboard: NSPasteboard,
        settings: AppSettings,
        source: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> ClipboardCapture? {
        guard !transientTypes.contains(where: { pasteboard.availableType(from: [$0]) != nil }) else { return nil }
        guard !SensitiveContentFilter.isExcluded(sourceBundleID: source?.bundleIdentifier, settings: settings) else {
            return nil
        }

        if !settings.ignoredTypes.contains(.file),
           let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            let paths = fileURLs.map { ClipboardNormalizer.filePath($0.path) }
            let content = ClipboardFileList.encode(paths: paths)
            let preview = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
            return capture(type: .file, preview: String(preview.prefix(500)),
                           content: content, data: nil, source: source)
        }

        if settings.keepImages,
           !settings.ignoredTypes.contains(.image),
           let capture = imageCapture(from: pasteboard, source: source, settings: settings) {
            return capture
        }

        guard let rawText = pasteboard.string(forType: .string),
              rawText.utf8.count <= maximumTextBytes else { return nil }
        let text = ClipboardNormalizer.text(rawText)
        guard !text.isEmpty,
              !SensitiveContentFilter.shouldIgnore(text: text, sourceBundleID: source?.bundleIdentifier, settings: settings) else { return nil }

        if let color = detectedColor(in: text), !settings.ignoredTypes.contains(.color) {
            return capture(type: .color, preview: color, content: color, data: nil, source: source)
        }

        if let normalized = ClipboardNormalizer.webURL(text), !settings.ignoredTypes.contains(.url) {
            return capture(type: .url, preview: normalized, content: normalized, data: nil, source: source)
        }

        let rawRTF = pasteboard.data(forType: .rtf)
        let rtf = rawRTF.flatMap { $0.count <= maximumTextBytes ? $0 : nil }
        let type: ClipboardItemType = rtf == nil ? .plainText : .richText
        guard !settings.ignoredTypes.contains(type) else { return nil }
        return capture(type: type, preview: String(text.prefix(500)), content: text, data: rtf, source: source)
    }

    private static func imageCapture(from pasteboard: NSPasteboard, source: NSRunningApplication?, settings: AppSettings) -> ClipboardCapture? {
        let data = pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff)
            ?? (pasteboard.readObjects(forClasses: [NSImage.self])?.first as? NSImage)?.tiffRepresentation
        guard let data,
              data.count <= settings.maximumImageMegabytes * 1_048_576 else { return nil }
        return ClipboardCapture(type: .image, preview: "Image", content: nil, richTextData: nil,
                                imageData: data, estimatedSize: Int64(data.count), fingerprint: ClipboardHash.data(data),
                                sourceApplication: source?.localizedName, sourceBundleIdentifier: source?.bundleIdentifier)
    }

    private static func capture(type: ClipboardItemType, preview: String, content: String, data: Data?, source: NSRunningApplication?) -> ClipboardCapture {
        let normalized: String
        switch type {
        case .url: normalized = ClipboardNormalizer.url(content)
        case .file:
            normalized = ClipboardFileList.fingerprintValue(paths: ClipboardFileList.paths(from: content))
        default: normalized = ClipboardNormalizer.text(content)
        }
        let size = Int64(content.utf8.count + (data?.count ?? 0))
        return ClipboardCapture(type: type, preview: preview, content: content, richTextData: data, imageData: nil,
                                estimatedSize: size, fingerprint: ClipboardHash.string("\(type.rawValue):\(normalized)"),
                                sourceApplication: source?.localizedName, sourceBundleIdentifier: source?.bundleIdentifier)
    }

    static func detectedColor(in text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let patterns = ["^#[0-9A-F]{3,4}$", "^#[0-9A-F]{6}$", "^#[0-9A-F]{8}$", "^0X[0-9A-F]{6}$", "^0X[0-9A-F]{8}$"]
        return patterns.contains(where: { value.range(of: $0, options: .regularExpression) != nil }) ? value : nil
    }
}
