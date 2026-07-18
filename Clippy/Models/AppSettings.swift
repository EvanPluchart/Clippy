import AppKit
import Carbon.HIToolbox
import Combine
import Foundation

enum DuplicatePolicy: String, Codable, CaseIterable, Identifiable {
    case mergeAll, consecutiveOnly, keepAll
    var id: String { rawValue }
    var title: String {
        switch self {
        case .mergeAll: "Fusionner tous les doublons"
        case .consecutiveOnly: "Doublons consécutifs seulement"
        case .keepAll: "Tout conserver"
        }
    }
}

enum RetentionPeriod: Int, Codable, CaseIterable, Identifiable {
    case sevenDays = 7, thirtyDays = 30, ninetyDays = 90, forever = 0
    var id: Int { rawValue }
    var title: String { rawValue == 0 ? "Indéfiniment" : "\(rawValue) jours" }
}

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Système"; case .light: "Clair"; case .dark: "Sombre" }
    }
    var colorScheme: NSAppearance.Name? {
        switch self { case .system: nil; case .light: .aqua; case .dark: .darkAqua }
    }
}

struct ShortcutConfiguration: Codable, Equatable {
    var keyCode: UInt32 = 9 // V
    var carbonModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    var isValid: Bool {
        KeyCodeMap.label(for: keyCode) != nil &&
        carbonModifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    var display: String {
        var result = ""
        if carbonModifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += KeyCodeMap.label(for: keyCode) ?? "?"
        return result
    }
}

struct AppSettings: Codable, Equatable {
    var monitoringEnabled = true
    var launchAtLogin = false
    var pollingInterval = 0.5
    var retentionPeriod = RetentionPeriod.thirtyDays
    var maximumItemCount = 1_000
    var maximumStorageMegabytes = 500
    var closeAfterCopy = true
    var automaticallyPaste = true
    var duplicatePolicy = DuplicatePolicy.consecutiveOnly
    var keepImages = true
    var maximumImageMegabytes = 25
    var showMenuBarItem = true
    var showDockIcon = false
    var appearance = AppAppearance.system
    var excludedBundleIdentifiers: [String] = []
    var ignoreSensitiveContent = true
    var sensitivePatterns: [String] = []
    var ignoredTypes: Set<ClipboardItemType> = []
    var quickPanelNearCursor = false
    var shortcut = ShortcutConfiguration()

    init() {}

    init(from decoder: Decoder) throws {
        let defaults = AppSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoringEnabled = (try? container.decode(Bool.self, forKey: .monitoringEnabled)) ?? defaults.monitoringEnabled
        launchAtLogin = (try? container.decode(Bool.self, forKey: .launchAtLogin)) ?? defaults.launchAtLogin
        pollingInterval = (try? container.decode(Double.self, forKey: .pollingInterval)) ?? defaults.pollingInterval
        retentionPeriod = (try? container.decode(RetentionPeriod.self, forKey: .retentionPeriod)) ?? defaults.retentionPeriod
        maximumItemCount = (try? container.decode(Int.self, forKey: .maximumItemCount)) ?? defaults.maximumItemCount
        maximumStorageMegabytes = (try? container.decode(Int.self, forKey: .maximumStorageMegabytes)) ?? defaults.maximumStorageMegabytes
        closeAfterCopy = (try? container.decode(Bool.self, forKey: .closeAfterCopy)) ?? defaults.closeAfterCopy
        automaticallyPaste = (try? container.decode(Bool.self, forKey: .automaticallyPaste)) ?? defaults.automaticallyPaste
        duplicatePolicy = (try? container.decode(DuplicatePolicy.self, forKey: .duplicatePolicy)) ?? defaults.duplicatePolicy
        keepImages = (try? container.decode(Bool.self, forKey: .keepImages)) ?? defaults.keepImages
        maximumImageMegabytes = (try? container.decode(Int.self, forKey: .maximumImageMegabytes)) ?? defaults.maximumImageMegabytes
        showMenuBarItem = (try? container.decode(Bool.self, forKey: .showMenuBarItem)) ?? defaults.showMenuBarItem
        showDockIcon = (try? container.decode(Bool.self, forKey: .showDockIcon)) ?? defaults.showDockIcon
        appearance = (try? container.decode(AppAppearance.self, forKey: .appearance)) ?? defaults.appearance
        excludedBundleIdentifiers = (try? container.decode([String].self, forKey: .excludedBundleIdentifiers)) ?? defaults.excludedBundleIdentifiers
        ignoreSensitiveContent = (try? container.decode(Bool.self, forKey: .ignoreSensitiveContent)) ?? defaults.ignoreSensitiveContent
        sensitivePatterns = (try? container.decode([String].self, forKey: .sensitivePatterns)) ?? defaults.sensitivePatterns
        ignoredTypes = (try? container.decode(Set<ClipboardItemType>.self, forKey: .ignoredTypes)) ?? defaults.ignoredTypes
        quickPanelNearCursor = (try? container.decode(Bool.self, forKey: .quickPanelNearCursor)) ?? defaults.quickPanelNearCursor
        shortcut = (try? container.decode(ShortcutConfiguration.self, forKey: .shortcut)) ?? defaults.shortcut

        pollingInterval = min(max(pollingInterval, 0.3), 2)
        maximumItemCount = min(max(maximumItemCount, 100), 10_000)
        maximumStorageMegabytes = min(max(maximumStorageMegabytes, 50), 5_000)
        maximumImageMegabytes = min(max(maximumImageMegabytes, 1), 200)
        excludedBundleIdentifiers = Self.normalizedLines(excludedBundleIdentifiers)
        sensitivePatterns = Self.normalizedLines(sensitivePatterns)
        if !shortcut.isValid { shortcut = defaults.shortcut }
        if !showMenuBarItem && !showDockIcon { showMenuBarItem = true }
    }

    private static func normalizedLines(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published private(set) var value: AppSettings
    private let defaults: UserDefaults
    private static let key = "Clippy.AppSettings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else {
            value = AppSettings()
        }
    }

    func update(_ newValue: AppSettings) {
        guard newValue != value else { return }
        value = newValue
        persist()
    }

    func reset() { update(AppSettings()) }

    private func persist() {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

enum KeyCodeMap {
    static let keys: [(String, UInt32)] = [
        ("A", 0), ("S", 1), ("D", 2), ("F", 3), ("H", 4), ("G", 5),
        ("Z", 6), ("X", 7), ("C", 8), ("V", 9), ("B", 11), ("Q", 12),
        ("W", 13), ("E", 14), ("R", 15), ("Y", 16), ("T", 17), ("1", 18),
        ("2", 19), ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25),
        ("7", 26), ("8", 28), ("0", 29), ("O", 31), ("U", 32), ("I", 34),
        ("P", 35), ("L", 37), ("J", 38), ("K", 40), ("N", 45), ("M", 46)
    ]
    static func label(for code: UInt32) -> String? { keys.first(where: { $0.1 == code })?.0 }
}
