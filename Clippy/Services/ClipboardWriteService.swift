import AppKit
import Foundation

@MainActor
final class ClipboardWriteService {
    private let storage: ClipboardFileStorage
    private let pasteboard: NSPasteboard

    init(storage: ClipboardFileStorage, pasteboard: NSPasteboard = .general) {
        self.storage = storage
        self.pasteboard = pasteboard
    }

    func write(_ item: ClipboardItem, plainTextOnly: Bool = false) async -> Int? {
        guard let prepared = await prepare(item, plainTextOnly: plainTextOnly) else { return nil }
        pasteboard.clearContents()
        let succeeded: Bool
        switch prepared {
        case .image(let data):
            succeeded = pasteboard.setData(data, forType: .png)
        case .richText(let rtf, let text):
            let wroteRTF = rtf.map { pasteboard.setData($0, forType: .rtf) } ?? false
            let wroteText = text.map { pasteboard.setString($0, forType: .string) } ?? false
            succeeded = wroteRTF || wroteText
        case .files(let urls):
            succeeded = pasteboard.writeObjects(urls)
        case .url(let url, let value):
            let wroteURL = pasteboard.writeObjects([url])
            let wroteText = pasteboard.setString(value, forType: .string)
            succeeded = wroteURL || wroteText
        case .text(let value):
            succeeded = pasteboard.setString(value, forType: .string)
        }
        return succeeded ? pasteboard.changeCount : nil
    }

    private func prepare(_ item: ClipboardItem, plainTextOnly: Bool) async -> PreparedClipboardContent? {
        if plainTextOnly, let content = item.content {
            if item.type == .file {
                return .text(ClipboardFileList.paths(from: content).joined(separator: "\n"))
            }
            return .text(content)
        }
        switch item.type {
        case .image:
            guard let path = item.relativeFilePath,
                  let data = await storage.data(relativePath: path) else {
                return nil
            }
            return .image(data)
        case .richText:
            guard item.richTextData != nil || item.content != nil else { return nil }
            return .richText(rtf: item.richTextData, text: item.content)
        case .file:
            let urls = ClipboardFileList.paths(from: item.content ?? "")
                .map { NSURL(fileURLWithPath: $0) }
            return urls.isEmpty ? nil : .files(urls)
        case .url:
            guard let value = item.content, let url = NSURL(string: value) else { return nil }
            return .url(url, value)
        default:
            guard let value = item.content else { return nil }
            return .text(value)
        }
    }
}

private enum PreparedClipboardContent {
    case image(Data)
    case richText(rtf: Data?, text: String?)
    case files([NSURL])
    case url(NSURL, String)
    case text(String)
}
