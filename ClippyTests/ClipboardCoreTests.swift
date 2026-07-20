import AppKit
import Carbon.HIToolbox
import Combine
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Clippy

final class ClipboardCoreTests: XCTestCase {
    func testReopeningMenuBarOnlyAppShowsHistory() {
        XCTAssertTrue(AppDelegate.shouldShowHistoryOnReopen(
            hasVisibleWindows: false,
            shouldSuppress: false
        ))
        XCTAssertFalse(AppDelegate.shouldShowHistoryOnReopen(
            hasVisibleWindows: true,
            shouldSuppress: false
        ))
        XCTAssertFalse(AppDelegate.shouldShowHistoryOnReopen(
            hasVisibleWindows: false,
            shouldSuppress: true
        ))
    }

    @MainActor
    func testQuickPanelCollectionBehaviorIsValid() {
        let behavior = QuickPanelController.collectionBehavior
        XCTAssertTrue(behavior.contains(.canJoinAllSpaces))
        XCTAssertFalse(behavior.contains(.moveToActiveSpace))
    }

    @MainActor
    func testQuickPanelNumericShortcutMapping() {
        XCTAssertEqual(QuickPanelController.numericIndex(forKeyCode: 18), 0)
        XCTAssertEqual(QuickPanelController.numericIndex(forKeyCode: 25), 8)
        XCTAssertNil(QuickPanelController.numericIndex(forKeyCode: 9))
    }

    @MainActor
    func testAutomaticPasteAuthorizationReturnsImmediatelyWhenGranted() {
        var requestCount = 0
        var settingsOpenCount = 0
        let service = AutomaticPasteService(
            preflightPostEventAccess: { true },
            requestPostEventAccess: {
                requestCount += 1
                return true
            },
            openAccessibilitySettings: {
                settingsOpenCount += 1
                return true
            }
        )

        XCTAssertEqual(service.requestAuthorizationFromUser(), .authorized)
        XCTAssertTrue(service.isAuthorized)
        XCTAssertFalse(service.requiresRelaunchAfterAuthorization)
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(settingsOpenCount, 0)
    }

    @MainActor
    func testAutomaticPasteAuthorizationOpensSettingsWhenPermissionIsMissing() {
        var settingsOpenCount = 0
        let service = AutomaticPasteService(
            preflightPostEventAccess: { false },
            requestPostEventAccess: { false },
            openAccessibilitySettings: {
                settingsOpenCount += 1
                return true
            }
        )

        XCTAssertEqual(service.requestAuthorizationFromUser(), .systemSettingsOpened)
        XCTAssertFalse(service.isAuthorized)
        XCTAssertEqual(service.lastOutcome, .permissionRequired)
        XCTAssertTrue(service.requiresRelaunchAfterAuthorization)
        XCTAssertEqual(settingsOpenCount, 1)
    }

    @MainActor
    func testAutomaticPasteAuthorizationReportsSettingsFailure() {
        let service = AutomaticPasteService(
            preflightPostEventAccess: { false },
            requestPostEventAccess: { false },
            openAccessibilitySettings: { false }
        )

        XCTAssertEqual(service.requestAuthorizationFromUser(), .systemSettingsUnavailable)
        XCTAssertFalse(service.isAuthorized)
        XCTAssertFalse(service.requiresRelaunchAfterAuthorization)
    }

    @MainActor
    func testAutomaticPasteAuthorizationClearsRelaunchWhenPermissionBecomesAvailable() {
        var isAuthorized = false
        let service = AutomaticPasteService(
            preflightPostEventAccess: { isAuthorized },
            requestPostEventAccess: { false },
            openAccessibilitySettings: { true }
        )

        XCTAssertEqual(service.requestAuthorizationFromUser(), .systemSettingsOpened)
        XCTAssertTrue(service.requiresRelaunchAfterAuthorization)

        isAuthorized = true
        service.refreshAuthorization()

        XCTAssertTrue(service.isAuthorized)
        XCTAssertFalse(service.requiresRelaunchAfterAuthorization)
    }

    func testApplicationRelauncherPassesProcessAndBundlePathAsShellArguments() {
        let arguments = ApplicationRelauncher.helperArguments(
            processIdentifier: 42,
            applicationPath: "/Applications/Clippy Test.app"
        )

        XCTAssertEqual(arguments[0], "-c")
        XCTAssertEqual(arguments[1], ApplicationRelauncher.helperScript)
        XCTAssertEqual(arguments[2], "clippy-relauncher")
        XCTAssertEqual(arguments[3], "42")
        XCTAssertEqual(arguments[4], "/Applications/Clippy Test.app")
        XCTAssertEqual(arguments[5], ApplicationRelauncher.relaunchArgument)
    }

    func testApplicationRelauncherHelperHasValidShellSyntax() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", "-c", ApplicationRelauncher.helperScript]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testTextNormalizationAndStableHash() {
        XCTAssertEqual(ClipboardNormalizer.text("  café\r\n"), "café")
        XCTAssertEqual(ClipboardHash.string(ClipboardNormalizer.text(" café ")),
                       ClipboardHash.string(ClipboardNormalizer.text("café")))
        XCTAssertNotEqual(ClipboardHash.string("one"), ClipboardHash.string("two"))
    }

    func testURLAndFileNormalization() {
        XCTAssertEqual(ClipboardNormalizer.url("HTTPS://EXAMPLE.COM/"), "https://example.com")
        XCTAssertEqual(ClipboardNormalizer.filePath("/tmp/a/../b"), "/tmp/b")
        let paths = ["/tmp/normal.txt", "/tmp/line\nbreak.txt"]
        XCTAssertEqual(ClipboardFileList.paths(from: ClipboardFileList.encode(paths: paths)), paths)
        XCTAssertEqual(ClipboardFileList.paths(from: "/tmp/legacy-one\n/tmp/legacy-two"),
                       ["/tmp/legacy-one", "/tmp/legacy-two"])
    }

    func testColorDetection() {
        XCTAssertEqual(ClipboardParser.detectedColor(in: " #12abEF "), "#12ABEF")
        XCTAssertEqual(ClipboardParser.detectedColor(in: "#fff"), "#FFF")
        XCTAssertEqual(ClipboardParser.detectedColor(in: "#abcd"), "#ABCD")
        XCTAssertEqual(ClipboardParser.detectedColor(in: "0x80ff0000"), "0X80FF0000")
        XCTAssertNil(ClipboardParser.detectedColor(in: "hello"))
    }

    func testSettingsSerialization() throws {
        var settings = AppSettings()
        settings.maximumItemCount = 2_400
        settings.ignoredTypes = [.image, .color]
        settings.excludedBundleIdentifiers = ["com.example.secret"]
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testSettingsMigrationUsesSafeDefaultsAndClampsValues() throws {
        let data = try XCTUnwrap(
            """
            {
              "monitoringEnabled": true,
              "pollingInterval": 99,
              "retentionPeriod": 999,
              "maximumItemCount": 1,
              "maximumStorageMegabytes": 99999,
              "maximumImageMegabytes": 0,
              "showMenuBarItem": false,
              "showDockIcon": false,
              "excludedBundleIdentifiers": [" com.example.Secret ", "com.example.Secret", ""],
              "sensitivePatterns": [" token ", "token"],
              "shortcut": {"keyCode": 999, "carbonModifiers": 0}
            }
            """.data(using: .utf8)
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(settings.pollingInterval, 2)
        XCTAssertEqual(settings.retentionPeriod, .thirtyDays)
        XCTAssertEqual(settings.maximumItemCount, 100)
        XCTAssertEqual(settings.maximumStorageMegabytes, 5_000)
        XCTAssertEqual(settings.maximumImageMegabytes, 1)
        XCTAssertTrue(settings.automaticallyPaste)
        XCTAssertTrue(settings.showMenuBarItem)
        XCTAssertFalse(settings.showDockIcon)
        XCTAssertEqual(settings.excludedBundleIdentifiers, ["com.example.Secret"])
        XCTAssertEqual(settings.sensitivePatterns, ["token"])
        XCTAssertEqual(settings.shortcut, ShortcutConfiguration())
    }

    @MainActor
    func testSettingsStoreDoesNotPublishIdenticalValues() {
        let suiteName = "ClippyTests.Settings.\(UUID())"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        var updates = 0
        let cancellable = store.objectWillChange.sink { updates += 1 }

        store.update(store.value)
        XCTAssertEqual(updates, 0)

        var changed = store.value
        changed.pollingInterval = 0.8
        store.update(changed)
        XCTAssertEqual(updates, 1)
        withExtendedLifetime(cancellable) {}
    }

    @MainActor
    func testLegacyPreferenceMigrationPreservesCurrentValues() throws {
        let suiteName = "ClippyTests.LegacyPreferences.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ClippyLegacyPreferences-\(UUID())")
        let preferencesURL = root.appending(path: "com.evpl.clippy.plist")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let currentSettings = Data("current".utf8)
        let legacySettings = Data("legacy".utf8)
        defaults.set(currentSettings, forKey: "Clippy.AppSettings.v1")
        let propertyList: [String: Any] = [
            "Clippy.AppSettings.v1": legacySettings,
            "Clippy.HasCompletedOnboarding.v1": true,
            "Unrelated": "ignored"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .binary,
            options: 0
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try data.write(to: preferencesURL)

        XCTAssertNil(LegacySandboxMigrationService.migratePreferencesIfNeeded(
            defaults: defaults,
            legacyPreferencesURL: preferencesURL
        ))
        XCTAssertEqual(defaults.data(forKey: "Clippy.AppSettings.v1"), currentSettings)
        XCTAssertTrue(defaults.bool(forKey: "Clippy.HasCompletedOnboarding.v1"))
        XCTAssertNil(defaults.object(forKey: "Unrelated"))
        XCTAssertTrue(defaults.bool(
            forKey: LegacySandboxMigrationService.preferencesMarkerKey
        ))
    }

    @MainActor
    func testLegacyHistoryMigrationIsSafeAndIdempotent() throws {
        let suiteName = "ClippyTests.LegacyHistory.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ClippyLegacyHistory-\(UUID())")
        let legacyRoot = root.appending(path: "legacy")
        let currentRoot = root.appending(path: "current")
        let legacyStore = legacyRoot.appending(path: "database/Clippy.store")
        let currentStore = currentRoot.appending(path: "database/Clippy.store")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(
            at: legacyStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: currentStore.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let schema = Schema([ClipboardItem.self])
        let textID = UUID()
        let imageID = UUID()
        let imagePath = "images/\(imageID.uuidString).png"
        let thumbnailPath = "thumbnails/\(imageID.uuidString).jpg"
        try FileManager.default.createDirectory(
            at: legacyRoot.appending(path: "images"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: legacyRoot.appending(path: "thumbnails"),
            withIntermediateDirectories: true
        )
        try Data("image".utf8).write(to: legacyRoot.appending(path: imagePath))
        try Data("thumbnail".utf8).write(to: legacyRoot.appending(path: thumbnailPath))

        do {
            let legacyConfiguration = ModelConfiguration(
                "LegacyFixture",
                schema: schema,
                url: legacyStore
            )
            let legacyContainer = try ModelContainer(
                for: schema,
                configurations: [legacyConfiguration]
            )
            let context = ModelContext(legacyContainer)
            context.insert(ClipboardItem(
                id: textID,
                type: .plainText,
                preview: "Recovered text",
                content: "Recovered text",
                estimatedSize: 14,
                fingerprint: "legacy-text"
            ))
            context.insert(ClipboardItem(
                id: imageID,
                type: .image,
                preview: "Recovered image",
                relativeFilePath: imagePath,
                relativeThumbnailPath: thumbnailPath,
                estimatedSize: 14,
                fingerprint: "legacy-image",
                imageWidth: 100,
                imageHeight: 50
            ))
            try context.save()
        }

        let currentConfiguration = ModelConfiguration(
            "CurrentFixture",
            schema: schema,
            url: currentStore
        )
        let currentContainer = try ModelContainer(
            for: schema,
            configurations: [currentConfiguration]
        )
        let firstResult = LegacySandboxMigrationService.migrateHistoryIfNeeded(
            schema: schema,
            currentContainer: currentContainer,
            currentRootURL: currentRoot,
            defaults: defaults,
            legacyRootURL: legacyRoot
        )
        XCTAssertEqual(firstResult, LegacySandboxMigrationResult(migratedItemCount: 2))
        let migratedItems = try ModelContext(currentContainer).fetch(
            FetchDescriptor<ClipboardItem>()
        )
        XCTAssertEqual(Set(migratedItems.map(\.id)), Set([textID, imageID]))
        XCTAssertEqual(
            try Data(contentsOf: currentRoot.appending(path: imagePath)),
            Data("image".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: currentRoot.appending(path: thumbnailPath)),
            Data("thumbnail".utf8)
        )

        let secondResult = LegacySandboxMigrationService.migrateHistoryIfNeeded(
            schema: schema,
            currentContainer: currentContainer,
            currentRootURL: currentRoot,
            defaults: defaults,
            legacyRootURL: legacyRoot
        )
        XCTAssertEqual(secondResult, LegacySandboxMigrationResult())
        XCTAssertEqual(
            try ModelContext(currentContainer).fetchCount(
                FetchDescriptor<ClipboardItem>()
            ),
            2
        )
    }

    func testShortcutValidationRejectsUnsafeOrUnknownKeys() {
        XCTAssertTrue(ShortcutConfiguration().isValid)
        XCTAssertFalse(ShortcutConfiguration(keyCode: 9, carbonModifiers: UInt32(shiftKey)).isValid)
        XCTAssertFalse(ShortcutConfiguration(keyCode: 999, carbonModifiers: UInt32(cmdKey)).isValid)
    }

    func testStrictURLRecognitionAvoidsFalsePositives() {
        XCTAssertEqual(ClipboardNormalizer.webURL("HTTPS://EXAMPLE.COM/"), "https://example.com")
        XCTAssertEqual(ClipboardNormalizer.webURL("mailto:hello@example.com"), "mailto:hello@example.com")
        XCTAssertNil(ClipboardNormalizer.webURL("example.com"))
        XCTAssertNil(ClipboardNormalizer.webURL("https:///missing-host"))
        XCTAssertNil(ClipboardNormalizer.webURL("https://example.com/space here"))
    }

    func testSensitiveContentRulesAreDefensive() {
        var settings = AppSettings()
        settings.excludedBundleIdentifiers = ["com.example.Secret"]
        XCTAssertTrue(SensitiveContentFilter.isExcluded(sourceBundleID: "COM.EXAMPLE.SECRET", settings: settings))
        XCTAssertFalse(SensitiveContentFilter.isExcluded(sourceBundleID: "com.example.safe", settings: settings))

        settings.sensitivePatterns = ["token=[A-Z0-9]+", "[invalid"]
        XCTAssertTrue(SensitiveContentFilter.shouldIgnore(
            text: "token=ABC123",
            sourceBundleID: "com.example.safe",
            settings: settings
        ))
        XCTAssertTrue(SensitiveContentFilter.shouldIgnore(
            text: "short secret",
            sourceBundleID: "com.1password.1password",
            settings: settings
        ))
        settings.ignoreSensitiveContent = false
        XCTAssertFalse(SensitiveContentFilter.shouldIgnore(
            text: "token=ABC123",
            sourceBundleID: "com.1password.1password",
            settings: settings
        ))
    }

    @MainActor
    func testParserDetectsTextURLFileAndImage() throws {
        var settings = AppSettings()
        settings.ignoreSensitiveContent = false
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClippyTests.\(UUID())"))

        pasteboard.clearContents()
        pasteboard.setString("Hello", forType: .string)
        XCTAssertEqual(ClipboardParser.parse(pasteboard, settings: settings, source: nil)?.type, .plainText)

        pasteboard.clearContents()
        pasteboard.setString("https://example.com/", forType: .string)
        XCTAssertEqual(ClipboardParser.parse(pasteboard, settings: settings, source: nil)?.type, .url)

        pasteboard.clearContents()
        pasteboard.writeObjects([NSURL(fileURLWithPath: "/tmp/test.txt")])
        XCTAssertEqual(ClipboardParser.parse(pasteboard, settings: settings, source: nil)?.type, .file)

        let image = makeImage(width: 2, height: 2, color: .red)
        pasteboard.clearContents()
        pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff)
        XCTAssertEqual(ClipboardParser.parse(pasteboard, settings: settings, source: nil)?.type, .image)
    }

    @MainActor
    func testParserPrioritizesFilesAndHonorsTransientMarkers() throws {
        var settings = AppSettings()
        settings.ignoreSensitiveContent = false
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClippyTests.\(UUID())"))
        let image = makeImage(width: 4, height: 4, color: .blue)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([NSURL(fileURLWithPath: "/tmp/photo.png")]))
        XCTAssertTrue(pasteboard.setData(try XCTUnwrap(image.tiffRepresentation), forType: .tiff))
        XCTAssertEqual(ClipboardParser.parse(pasteboard, settings: settings, source: nil)?.type, .file)

        pasteboard.clearContents()
        pasteboard.setString("must not be recorded", forType: .string)
        pasteboard.setData(
            Data(),
            forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        )
        XCTAssertNil(ClipboardParser.parse(pasteboard, settings: settings, source: nil))
    }

    @MainActor
    func testDuplicatePolicies() throws {
        let repository = try makeRepository()
        let capture = makeCapture("same")
        XCTAssertNotNil(repository.record(capture, storedImage: nil, policy: .consecutiveOnly))
        XCTAssertNil(repository.record(capture, storedImage: nil, policy: .consecutiveOnly))
        XCTAssertEqual(repository.items.count, 1)
        XCTAssertNotNil(repository.record(capture, storedImage: nil, policy: .keepAll))
        XCTAssertEqual(repository.items.count, 2)
    }

    @MainActor
    func testRetentionByAgeCountSizeAndPinnedPreservation() throws {
        let repository = try makeRepository()
        for index in 0..<5 { _ = repository.record(makeCapture("item-\(index)", bytes: 100), storedImage: nil, policy: .keepAll) }
        let oldest = try XCTUnwrap(repository.items.last)
        oldest.createdAt = Calendar.current.date(byAdding: .day, value: -40, to: .now)!
        oldest.lastUsedAt = oldest.createdAt
        oldest.isPinned = true

        var settings = AppSettings()
        settings.retentionPeriod = .thirtyDays
        settings.maximumItemCount = 3
        settings.maximumStorageMegabytes = 500
        let countVictims = repository.retentionCandidates(settings: settings)
        XCTAssertEqual(countVictims.count, 2)
        XCTAssertFalse(countVictims.contains(where: { $0.id == oldest.id }))

        settings.maximumItemCount = 100
        settings.maximumStorageMegabytes = 0
        let sizeVictims = repository.retentionCandidates(settings: settings)
        XCTAssertEqual(sizeVictims.count, 4)
        XCTAssertFalse(sizeVictims.contains(where: { $0.isPinned }))
    }

    func testImageStorageRoundTripAndOrphanCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClippyTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ClipboardFileStorage(rootURL: root)
        let image = makeImage(width: 20, height: 10, color: .blue)
        let stored = try await storage.storeImage(try XCTUnwrap(image.tiffRepresentation))
        XCTAssertGreaterThan(stored.width, 0)
        XCTAssertEqual(stored.width, stored.height * 2)
        let roundTrip = await storage.data(relativePath: stored.imagePath)
        let protectedFreshFiles = await storage.removeOrphans(referencedPaths: [])
        let orphanResult = await storage.removeOrphans(referencedPaths: [], minimumAge: 0)
        XCTAssertNotNil(roundTrip)
        XCTAssertEqual(protectedFreshFiles.removedFiles, 0)
        XCTAssertEqual(orphanResult.removedFiles, 2)
        XCTAssertGreaterThan(orphanResult.reclaimedBytes, 0)
    }

    func testImageStorageIsTransactionalAndRejectsUnsafePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClippyTests-\(UUID())")
        let outside = FileManager.default.temporaryDirectory.appending(path: "ClippySecret-\(UUID())")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let storage = ClipboardFileStorage(rootURL: root)
        let imageData = try XCTUnwrap(makeImage(width: 40, height: 20, color: .purple).tiffRepresentation)

        do {
            _ = try await storage.storeImage(imageData, maximumBytes: 1)
            XCTFail("An oversized normalized image should be rejected")
        } catch let error as ClipboardStorageError {
            guard case .imageTooLarge = error else {
                return XCTFail("Unexpected storage error: \(error)")
            }
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "images").path).isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "thumbnails").path).isEmpty)
        let traversedData = await storage.data(relativePath: "../outside.txt")
        XCTAssertNil(traversedData)

        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside.appending(path: "secret.txt"))
        try FileManager.default.createSymbolicLink(
            at: root.appending(path: "images/escape"),
            withDestinationURL: outside
        )
        let escapedData = await storage.data(relativePath: "images/escape/secret.txt")
        XCTAssertNil(escapedData)
    }

    func testNormalizedImageFingerprintAndErase() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClippyTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ClipboardFileStorage(rootURL: root)
        let image = makeImage(width: 32, height: 18, color: .systemTeal)
        var proposedRect = NSRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        let tiff = try encodedImage(cgImage, type: .tiff)
        let png = try encodedImage(cgImage, type: .png)

        let first = try await storage.storeImage(tiff)
        let second = try await storage.storeImage(png)
        XCTAssertEqual(first.fingerprint, second.fingerprint)

        try await storage.eraseAllFiles()
        let firstDataAfterErase = await storage.data(relativePath: first.imagePath)
        let secondDataAfterErase = await storage.data(relativePath: second.imagePath)
        XCTAssertNil(firstDataAfterErase)
        XCTAssertNil(secondDataAfterErase)
    }

    @MainActor
    func testRepositoryBatchOperationsMaintainStatistics() throws {
        let repository = try makeRepository()
        for index in 0..<3 {
            _ = repository.record(makeCapture("item-\(index)", bytes: Int64(index + 1)), storedImage: nil, policy: .keepAll)
        }
        let selected = Set(repository.items.prefix(2).map(\.id))
        repository.setPinned(ids: selected, pinned: true)
        XCTAssertEqual(repository.pinnedCount, 2)
        XCTAssertEqual(repository.totalBytes, 6)

        let deletedPaths = repository.delete(ids: selected)
        XCTAssertTrue(deletedPaths.isEmpty)
        XCTAssertEqual(repository.items.count, 1)
        XCTAssertEqual(repository.pinnedCount, 0)
        XCTAssertEqual(repository.totalBytes, repository.items[0].estimatedSize)
    }

    @MainActor
    func testClipboardWriterUsesIsolatedPasteboardForEveryCoreType() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ClippyTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = ClipboardFileStorage(rootURL: root)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClippyWriterTests.\(UUID())"))
        let writer = ClipboardWriteService(storage: storage, pasteboard: pasteboard)

        let text = ClipboardItem(
            type: .plainText,
            preview: "Hello",
            content: "Hello",
            estimatedSize: 5,
            fingerprint: "text"
        )
        let textChange = await writer.write(text)
        XCTAssertNotNil(textChange)
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello")

        let url = ClipboardItem(
            type: .url,
            preview: "https://example.com",
            content: "https://example.com",
            estimatedSize: 19,
            fingerprint: "url"
        )
        let urlChange = await writer.write(url)
        XCTAssertNotNil(urlChange)
        XCTAssertEqual(pasteboard.string(forType: .string), "https://example.com")

        let file = ClipboardItem(
            type: .file,
            preview: "one.txt",
            content: ClipboardFileList.encode(paths: ["/tmp/one.txt", "/tmp/two.txt"]),
            estimatedSize: 24,
            fingerprint: "file"
        )
        let fileChange = await writer.write(file)
        XCTAssertNotNil(fileChange)
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        XCTAssertEqual(fileURLs?.map(\.path), ["/tmp/one.txt", "/tmp/two.txt"])

        let imageData = try XCTUnwrap(makeImage(width: 12, height: 8, color: .orange).tiffRepresentation)
        let stored = try await storage.storeImage(imageData)
        let image = ClipboardItem(
            type: .image,
            preview: "Image",
            relativeFilePath: stored.imagePath,
            estimatedSize: stored.byteCount,
            fingerprint: stored.fingerprint
        )
        let imageChange = await writer.write(image)
        XCTAssertNotNil(imageChange)
        XCTAssertNotNil(pasteboard.data(forType: .png))
    }

    @MainActor private func makeRepository() throws -> ClipboardRepository {
        let schema = Schema([ClipboardItem.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        return ClipboardRepository(container: container)
    }
    private func makeCapture(_ value: String, bytes: Int64 = 10) -> ClipboardCapture {
        ClipboardCapture(type: .plainText, preview: value, content: value, richTextData: nil, imageData: nil,
                         estimatedSize: bytes, fingerprint: ClipboardHash.string(value), sourceApplication: nil, sourceBundleIdentifier: nil)
    }

    private func makeImage(width: CGFloat, height: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func encodedImage(_ image: CGImage, type: UTType) throws -> Data {
        let output = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return output as Data
    }
}
