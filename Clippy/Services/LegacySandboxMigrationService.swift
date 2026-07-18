import Foundation
@preconcurrency import SwiftData

struct LegacySandboxMigrationResult: Equatable {
    var migratedItemCount = 0
    var warning: String?
}

@MainActor
enum LegacySandboxMigrationService {
    static let preferencesMarkerKey = "Clippy.LegacySandboxPreferencesMigration.v1"
    static let historyMarkerKey = "Clippy.LegacySandboxHistoryMigration.v1"

    private static let preferenceKeys = [
        "Clippy.AppSettings.v1",
        "Clippy.HasCompletedOnboarding.v1",
        "Clippy.LastCleanupSummary"
    ]

    static func legacyRootURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appending(path: "Library/Containers/com.evpl.clippy/Data/Library/Application Support/Clippy")
            .standardizedFileURL
    }

    static func legacyPreferencesURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appending(path: "Library/Containers/com.evpl.clippy/Data/Library/Preferences/com.evpl.clippy.plist")
            .standardizedFileURL
    }

    static func migratePreferencesIfNeeded(
        defaults: UserDefaults = .standard,
        legacyPreferencesURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        guard !defaults.bool(forKey: preferencesMarkerKey) else { return nil }
        let sourceURL = legacyPreferencesURL ?? self.legacyPreferencesURL()
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            defaults.set(true, forKey: preferencesMarkerKey)
            return nil
        }

        do {
            let data = try Data(contentsOf: sourceURL)
            guard let propertyList = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            for key in preferenceKeys where defaults.object(forKey: key) == nil {
                if let value = propertyList[key] {
                    defaults.set(value, forKey: key)
                }
            }
            defaults.set(true, forKey: preferencesMarkerKey)
            return nil
        } catch {
            Log.storage.error(
                "Legacy preference migration failed: \(error.localizedDescription, privacy: .public)"
            )
            return "Les anciens réglages n’ont pas pu être récupérés automatiquement."
        }
    }

    static func migrateHistoryIfNeeded(
        schema: Schema,
        currentContainer: ModelContainer,
        currentRootURL: URL,
        defaults: UserDefaults = .standard,
        legacyRootURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> LegacySandboxMigrationResult {
        guard !defaults.bool(forKey: historyMarkerKey) else {
            return LegacySandboxMigrationResult()
        }

        let sourceRoot = (legacyRootURL ?? self.legacyRootURL()).standardizedFileURL
        let legacyStoreURL = sourceRoot.appending(path: "database/Clippy.store")
        guard fileManager.fileExists(atPath: legacyStoreURL.path) else {
            defaults.set(true, forKey: historyMarkerKey)
            return LegacySandboxMigrationResult()
        }

        do {
            let legacyConfiguration = ModelConfiguration(
                "ClippyLegacy",
                schema: schema,
                url: legacyStoreURL,
                allowsSave: false
            )
            let legacyContainer = try ModelContainer(
                for: schema,
                configurations: [legacyConfiguration]
            )
            let legacyContext = ModelContext(legacyContainer)
            var descriptor = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .forward)]
            )
            descriptor.fetchLimit = 10_000
            let legacyItems = try legacyContext.fetch(descriptor)

            let currentContext = ModelContext(currentContainer)
            currentContext.autosaveEnabled = false
            let existingIDs = Set(try currentContext.fetch(
                FetchDescriptor<ClipboardItem>()
            ).map(\.id))
            var migratedCount = 0
            var missingImageCount = 0

            for legacyItem in legacyItems where !existingIDs.contains(legacyItem.id) {
                let imagePath = copyStoredFile(
                    relativePath: legacyItem.relativeFilePath,
                    from: sourceRoot,
                    to: currentRootURL,
                    fileManager: fileManager
                )
                let thumbnailPath = copyStoredFile(
                    relativePath: legacyItem.relativeThumbnailPath,
                    from: sourceRoot,
                    to: currentRootURL,
                    fileManager: fileManager
                )
                if legacyItem.type == .image, imagePath == nil {
                    missingImageCount += 1
                    continue
                }

                currentContext.insert(ClipboardItem(
                    id: legacyItem.id,
                    type: legacyItem.type,
                    createdAt: legacyItem.createdAt,
                    lastUsedAt: legacyItem.lastUsedAt,
                    preview: legacyItem.preview,
                    content: legacyItem.content,
                    richTextData: legacyItem.richTextData,
                    relativeFilePath: imagePath,
                    relativeThumbnailPath: thumbnailPath,
                    estimatedSize: legacyItem.estimatedSize,
                    useCount: legacyItem.useCount,
                    isPinned: legacyItem.isPinned,
                    sourceApplication: legacyItem.sourceApplication,
                    sourceBundleIdentifier: legacyItem.sourceBundleIdentifier,
                    fingerprint: legacyItem.fingerprint,
                    imageWidth: legacyItem.imageWidth,
                    imageHeight: legacyItem.imageHeight
                ))
                migratedCount += 1
            }

            if currentContext.hasChanges {
                try currentContext.save()
            }
            defaults.set(true, forKey: historyMarkerKey)
            Log.storage.notice(
                "Legacy sandbox migration imported \(migratedCount, privacy: .public) item(s)"
            )
            let warning = missingImageCount > 0
                ? "\(missingImageCount) ancienne(s) image(s) n’ont pas pu être récupérées."
                : nil
            return LegacySandboxMigrationResult(
                migratedItemCount: migratedCount,
                warning: warning
            )
        } catch {
            Log.storage.error(
                "Legacy history migration failed: \(error.localizedDescription, privacy: .public)"
            )
            return LegacySandboxMigrationResult(
                warning: "L’ancien historique sandboxé n’a pas pu être récupéré automatiquement."
            )
        }
    }

    private static func copyStoredFile(
        relativePath: String?,
        from sourceRoot: URL,
        to destinationRoot: URL,
        fileManager: FileManager
    ) -> String? {
        guard let relativePath,
              let sourceURL = safeURL(relativePath: relativePath, root: sourceRoot),
              let destinationURL = safeURL(relativePath: relativePath, root: destinationRoot),
              fileManager.fileExists(atPath: sourceURL.path) else {
            return nil
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            return relativePath
        }
        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return relativePath
        } catch {
            Log.storage.error(
                "Legacy stored-file migration failed: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func safeURL(relativePath: String, root: URL) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = resolvedRoot
            .appending(path: relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        return candidate.path.hasPrefix(rootPrefix) ? candidate : nil
    }
}
