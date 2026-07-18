import CryptoKit
import Foundation
import OSLog

enum ClipboardNormalizer {
    static func text(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    static func url(_ value: String) -> String {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return text(value)
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if components.path == "/" { components.path = "" }
        return components.string ?? text(value)
    }

    static func webURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "ftp", "mailto", "tel"].contains(scheme) else {
            return nil
        }
        if ["http", "https", "ftp"].contains(scheme), components.host?.isEmpty != false {
            return nil
        }
        return url(trimmed)
    }

    static func filePath(_ value: String) -> String {
        URL(fileURLWithPath: value).standardizedFileURL.path
    }
}

enum ClipboardFileList {
    private static let prefix = "clippy-file-list-v1:"

    static func encode(paths: [String]) -> String {
        let normalized = paths.map(ClipboardNormalizer.filePath)
        guard let data = try? JSONEncoder().encode(normalized),
              let json = String(data: data, encoding: .utf8) else {
            return normalized.joined(separator: "\n")
        }
        return prefix + json
    }

    static func paths(from storedValue: String) -> [String] {
        if storedValue.hasPrefix(prefix) {
            let json = String(storedValue.dropFirst(prefix.count))
            if let data = json.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String].self, from: data) {
                return decoded.map(ClipboardNormalizer.filePath)
            }
            return []
        }
        return storedValue
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { ClipboardNormalizer.filePath(String($0)) }
    }

    static func fingerprintValue(paths: [String]) -> String {
        paths.map(ClipboardNormalizer.filePath).joined(separator: "\0")
    }
}

enum ClipboardHash {
    static func string(_ value: String) -> String { data(Data(value.utf8)) }
    static func data(_ value: Data) -> String {
        SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined()
    }
}

enum SensitiveContentFilter {
    static func isExcluded(sourceBundleID: String?, settings: AppSettings) -> Bool {
        guard let sourceBundleID else { return false }
        return settings.excludedBundleIdentifiers.contains {
            $0.compare(sourceBundleID, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    static func shouldIgnore(text: String, sourceBundleID: String?, settings: AppSettings) -> Bool {
        guard settings.ignoreSensitiveContent else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        for pattern in settings.sensitivePatterns where !pattern.isEmpty && pattern.count <= 512 {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            if expression.firstMatch(in: trimmed, range: range) != nil { return true }
        }
        let passwordManagers = ["1password", "bitwarden", "lastpass", "keepass", "dashlane", "protonpass"]
        if let sourceBundleID,
           passwordManagers.contains(where: { sourceBundleID.lowercased().contains($0) }),
           trimmed.count <= 128 {
            return true
        }
        return false
    }
}

extension Int64 {
    var formattedBytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

enum Log {
    static let general = Logger(subsystem: "com.evpl.clippy", category: "general")
    static let storage = Logger(subsystem: "com.evpl.clippy", category: "storage")
    // Never pass clipboard payloads to these loggers.
}
