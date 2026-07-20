import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
@preconcurrency import SwiftData
import SwiftUI

struct AppNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case information
        case warning
        case error
    }

    let id = UUID()
    let message: String
    let kind: Kind
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let settingsStore: SettingsStore
    let repository: ClipboardRepository
    let fileStorage: ClipboardFileStorage
    let thumbnailCache: ThumbnailCache
    let monitor: ClipboardMonitorService
    let cleanup: ClipboardCleanupService
    let writer: ClipboardWriteService
    let shortcut: GlobalShortcutService
    let automaticPaste: AutomaticPasteService

    @Published private(set) var storageWarning: String?
    @Published private(set) var notice: AppNotice?

    private let quickPanel = QuickPanelController()
    private let historyWindow = HistoryWindowController()
    private let settingsWindow = SettingsWindowController()
    private let onboardingWindow = OnboardingWindowController()
    private var subscriptions = Set<AnyCancellable>()
    private var appliedSettings: AppSettings?
    private var isPresentingModal = false
    private var quickPanelSelectionInProgress = false
    private var started = false
    private var noticeDismissTask: Task<Void, Never>?

    private init() {
        let shouldMigrateLegacySandbox = Self.shouldMigrateLegacySandbox
        var initializationWarnings: [String] = []
        if shouldMigrateLegacySandbox,
           let warning = LegacySandboxMigrationService.migratePreferencesIfNeeded() {
            initializationWarnings.append(warning)
        }
        let settings = SettingsStore()
        let rootURL = Self.dataRootURL()
        let storage = ClipboardFileStorage(rootURL: rootURL)
        let schema = Schema([ClipboardItem.self])
        let databaseDirectory = rootURL.appending(path: "database", directoryHint: .isDirectory)

        do {
            try FileManager.default.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        } catch {
            initializationWarnings.append(
                String(
                    localized: "Le dossier de données n’a pas pu être créé. L’historique ne sera pas persistant."
                )
            )
            Log.storage.error("Database directory creation failed: \(error.localizedDescription, privacy: .public)")
        }

        let configuration = ModelConfiguration(
            "Clippy",
            schema: schema,
            url: databaseDirectory.appending(path: "Clippy.store")
        )
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            Log.storage.fault("Persistent store failed, using memory store: \(error.localizedDescription, privacy: .public)")
            initializationWarnings.append(
                String(
                    localized: "La base locale n’a pas pu être ouverte. Cette session utilise un historique temporaire."
                )
            )
            guard let memoryContainer = try? ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            ) else {
                fatalError("Clippy could not initialize a SwiftData container.")
            }
            container = memoryContainer
        }

        if shouldMigrateLegacySandbox {
            let migration = LegacySandboxMigrationService.migrateHistoryIfNeeded(
                schema: schema,
                currentContainer: container,
                currentRootURL: rootURL
            )
            if let warning = migration.warning {
                initializationWarnings.append(warning)
            }
        }

        let repository = ClipboardRepository(container: container)
        let pasteService = AutomaticPasteService()

        settingsStore = settings
        fileStorage = storage
        thumbnailCache = ThumbnailCache()
        self.repository = repository
        writer = ClipboardWriteService(storage: storage)
        monitor = ClipboardMonitorService(repository: repository, settingsStore: settings, storage: storage)
        cleanup = ClipboardCleanupService(repository: repository, settingsStore: settings, storage: storage)
        shortcut = GlobalShortcutService()
        automaticPaste = pasteService
        storageWarning = initializationWarnings.isEmpty
            ? nil
            : initializationWarnings.joined(separator: " ")

        settings.$value.dropFirst().sink { [weak self] value in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
                self?.applyChangedSettings(value)
            }
        }.store(in: &subscriptions)
        repository.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        monitor.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        cleanup.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        shortcut.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
        pasteService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }

    func start() {
        guard !started else { return }
        started = true
        applyChangedSettings(settingsStore.value)
        monitor.start()
        cleanup.start()
    }

    func shutdown() {
        noticeDismissTask?.cancel()
        monitor.pause()
        shortcut.unregister()
        quickPanel.shutdown()
    }

    func registerShortcut() {
        _ = shortcut.register(configuration: settingsStore.value.shortcut) { [weak self] in
            self?.showQuickPanel()
        }
    }

    @discardableResult
    func applyShortcut(_ configuration: ShortcutConfiguration) -> Bool {
        guard shortcut.register(configuration: configuration, action: { [weak self] in
            self?.showQuickPanel()
        }) else {
            return false
        }
        var settings = settingsStore.value
        settings.shortcut = configuration
        settingsStore.update(settings)
        return true
    }

    func showQuickPanel() {
        quickPanel.show(state: self, nearCursor: settingsStore.value.quickPanelNearCursor)
    }

    func hideQuickPanel() {
        quickPanel.hide()
    }

    func requestAutomaticPasteAuthorization() {
        quickPanel.hide()
        let result = automaticPaste.requestAuthorizationFromUser()
        guard result == .systemSettingsUnavailable else { return }
        postNotice(
            String(
                localized: "Impossible d’ouvrir les réglages Accessibilité. Ouvrez Réglages Système > Confidentialité et sécurité > Accessibilité."
            ),
            kind: .error,
            duration: .seconds(10)
        )
        NSSound.beep()
    }

    func relaunchAfterAutomaticPasteAuthorization() {
        quickPanel.hide()
        do {
            try ApplicationRelauncher.relaunch()
        } catch {
            postNotice(
                String(
                    localized: "Clippy n’a pas pu se relancer. Quittez-la puis rouvrez-la manuellement."
                ),
                kind: .error,
                duration: .seconds(10)
            )
            Log.general.error("Application relaunch failed: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    func showHistory() {
        quickPanel.hide()
        historyWindow.show(state: self)
    }

    func showSettings() {
        quickPanel.hide()
        settingsWindow.show(state: self)
    }

    func showOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "Clippy.HasCompletedOnboarding.v1") else { return }
        showOnboarding()
    }

    func showOnboarding() {
        quickPanel.hide()
        onboardingWindow.show(state: self) {
            UserDefaults.standard.set(true, forKey: "Clippy.HasCompletedOnboarding.v1")
        }
    }

    func completeOnboarding(openQuickPanel: Bool) {
        UserDefaults.standard.set(true, forKey: "Clippy.HasCompletedOnboarding.v1")
        onboardingWindow.close()
        guard openQuickPanel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.showQuickPanel()
        }
    }

    func copy(_ item: ClipboardItem, plainTextOnly: Bool = false) {
        Task {
            guard let change = await writer.write(item, plainTextOnly: plainTextOnly) else {
                postNotice(String(localized: "Cet élément n’est plus disponible."), kind: .error)
                NSSound.beep()
                return
            }
            monitor.suppress(changeCount: change)
            repository.markUsed(item)
            postNotice(String(localized: "Copié dans le presse-papiers."))
        }
    }

    func selectFromQuickPanel(_ item: ClipboardItem, plainTextOnly: Bool = false) {
        guard !quickPanelSelectionInProgress else { return }
        quickPanelSelectionInProgress = true
        Task {
            defer { quickPanelSelectionInProgress = false }
            guard let change = await writer.write(item, plainTextOnly: plainTextOnly) else {
                postNotice(String(localized: "Cet élément n’est plus disponible."), kind: .error)
                NSSound.beep()
                return
            }
            monitor.suppress(changeCount: change)
            repository.markUsed(item)

            let shouldPaste = quickPanel.hasPreviousApplication && settingsStore.value.automaticallyPaste
            if shouldPaste {
                automaticPaste.refreshAuthorization()
                if !automaticPaste.isAuthorized, !automaticPaste.requestAuthorization() {
                    postNotice(
                        String(
                            localized: "L’élément est copié. Autorisez le collage automatique, puis sélectionnez-le à nouveau."
                        ),
                        kind: .warning,
                        duration: .seconds(8)
                    )
                    return
                }
            }

            let shouldClose = shouldPaste || settingsStore.value.closeAfterCopy
            if shouldClose {
                quickPanel.completeSelection(
                    pasteIntoPreviousApplication: shouldPaste,
                    pasteService: automaticPaste
                ) { [weak self] outcome in
                    self?.handleAutomaticPasteOutcome(outcome)
                }
            } else {
                postNotice(String(localized: "Copié dans le presse-papiers."))
            }
        }
    }

    func postNotice(
        _ message: String,
        kind: AppNotice.Kind = .information,
        duration: Duration = .seconds(4)
    ) {
        noticeDismissTask?.cancel()
        let newNotice = AppNotice(message: message, kind: kind)
        notice = newNotice
        noticeDismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, self?.notice?.id == newNotice.id else { return }
            self?.notice = nil
        }
    }

    func clearNotice() {
        noticeDismissTask?.cancel()
        noticeDismissTask = nil
        notice = nil
    }

    private func handleAutomaticPasteOutcome(_ outcome: AutomaticPasteOutcome) {
        switch outcome {
        case .pasted:
            clearNotice()
        case .copiedOnly:
            postNotice(String(localized: "Copié dans le presse-papiers."))
        case .permissionRequired:
            postNotice(
                String(
                    localized: "L’élément est copié, mais macOS n’autorise pas encore le collage automatique."
                ),
                kind: .warning,
                duration: .seconds(8)
            )
            reopenQuickPanelAfterPasteFailure()
        case .targetUnavailable:
            postNotice(
                String(
                    localized: "L’élément est copié, mais l’application précédente n’est plus disponible."
                ),
                kind: .warning,
                duration: .seconds(8)
            )
            reopenQuickPanelAfterPasteFailure()
        case .eventPostingFailed:
            postNotice(
                String(
                    localized: "L’élément est copié, mais macOS n’a pas pu envoyer ⌘V. Collez-le manuellement ou réessayez."
                ),
                kind: .error,
                duration: .seconds(8)
            )
            reopenQuickPanelAfterPasteFailure()
        }
    }

    private func reopenQuickPanelAfterPasteFailure() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.quickPanel.isVisibleOrOpening else { return }
            self.showQuickPanel()
        }
    }

    func delete(_ items: [ClipboardItem]) {
        let paths = repository.delete(items)
        thumbnailCache.remove(relativePaths: paths)
        Task { await fileStorage.delete(relativePaths: paths) }
    }

    func clearHistory(includePinned: Bool = false) {
        let paths = repository.clear(includePinned: includePinned)
        thumbnailCache.remove(relativePaths: paths)
        Task { await fileStorage.delete(relativePaths: paths) }
    }

    func confirmAndClearHistory() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Vider l’historique non épinglé ?")
        alert.informativeText = String(
            localized: "Les éléments épinglés seront conservés. Cette action est irréversible."
        )
        alert.addButton(withTitle: String(localized: "Vider"))
        alert.addButton(withTitle: String(localized: "Annuler"))
        isPresentingModal = true
        let response = alert.runModal()
        isPresentingModal = false
        guard response == .alertFirstButtonReturn else { return }
        clearHistory()
    }

    func eraseEverything() {
        let itemCount = repository.items.count
        _ = repository.clear(includePinned: true)
        guard itemCount == 0 || repository.items.isEmpty else {
            postNotice(
                String(
                    localized: "Les données n’ont pas été effacées, car la base locale n’a pas pu être mise à jour."
                ),
                kind: .error,
                duration: .seconds(8)
            )
            NSSound.beep()
            return
        }
        thumbnailCache.removeAll()
        Task {
            do {
                try await fileStorage.eraseAllFiles()
                postNotice(String(localized: "Toutes les données locales ont été effacées."))
            } catch {
                postNotice(
                    String(localized: "Certains fichiers locaux n’ont pas pu être effacés."),
                    kind: .error,
                    duration: .seconds(8)
                )
                Log.storage.error("Full erase failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func setMenuBarItemVisible(_ visible: Bool) {
        var settings = settingsStore.value
        settings.showMenuBarItem = visible
        if !visible { settings.showDockIcon = true }
        settingsStore.update(settings)
    }

    func setDockIconVisible(_ visible: Bool) {
        var settings = settingsStore.value
        settings.showDockIcon = visible
        if !visible { settings.showMenuBarItem = true }
        settingsStore.update(settings)
    }

    func refreshSystemState() {
        automaticPaste.refreshAuthorization()
    }

    #if DEBUG || QA
    func seedPreviewDataIfRequested() {
        guard ProcessInfo.processInfo.environment["CLIPPY_QA_SEED_DATA"] == "1",
              repository.items.isEmpty else {
            return
        }
        Task {
            let samples: [ClipboardCapture] = [
                ClipboardCapture(
                    type: .plainText,
                    preview: L10n.qaSampleText,
                    content: L10n.qaSampleText,
                    richTextData: nil,
                    imageData: nil,
                    estimatedSize: 68,
                    fingerprint: ClipboardHash.string("qa-text"),
                    sourceApplication: "Xcode",
                    sourceBundleIdentifier: "com.apple.dt.Xcode"
                ),
                ClipboardCapture(
                    type: .url,
                    preview: "https://github.com/EvanPluchart/Clippy",
                    content: "https://github.com/EvanPluchart/Clippy",
                    richTextData: nil,
                    imageData: nil,
                    estimatedSize: 41,
                    fingerprint: ClipboardHash.string("qa-url"),
                    sourceApplication: "Safari",
                    sourceBundleIdentifier: "com.apple.Safari"
                ),
                ClipboardCapture(
                    type: .color,
                    preview: "#5B5BF7",
                    content: "#5B5BF7",
                    richTextData: nil,
                    imageData: nil,
                    estimatedSize: 7,
                    fingerprint: ClipboardHash.string("qa-color"),
                    sourceApplication: "Figma",
                    sourceBundleIdentifier: "com.figma.Desktop"
                ),
                ClipboardCapture(
                    type: .file,
                    preview: "Project-Brief.pdf",
                    content: "/Users/demo/Documents/Project-Brief.pdf",
                    richTextData: nil,
                    imageData: nil,
                    estimatedSize: 39,
                    fingerprint: ClipboardHash.string("qa-file"),
                    sourceApplication: "Finder",
                    sourceBundleIdentifier: "com.apple.finder"
                )
            ]
            for sample in samples {
                _ = repository.record(sample, storedImage: nil, policy: .keepAll)
            }

            let image = NSImage(size: NSSize(width: 800, height: 480))
            image.lockFocus()
            NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.28, alpha: 1).setFill()
            NSRect(origin: .zero, size: image.size).fill()
            NSColor(calibratedRed: 0.36, green: 0.36, blue: 0.97, alpha: 1).setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 110, y: 80, width: 580, height: 320),
                xRadius: 42,
                yRadius: 42
            ).fill()
            image.unlockFocus()
            if let data = image.tiffRepresentation,
               let stored = try? await fileStorage.storeImage(data) {
                let capture = ClipboardCapture(
                    type: .image,
                    preview: L10n.qaImagePreview,
                    content: nil,
                    richTextData: nil,
                    imageData: data,
                    estimatedSize: Int64(data.count),
                    fingerprint: ClipboardHash.data(data),
                    sourceApplication: L10n.qaPreviewApplication,
                    sourceBundleIdentifier: "com.apple.Preview"
                )
                _ = repository.record(capture, storedImage: stored, policy: .keepAll)
            }
        }
    }
    #endif

    var shouldSuppressApplicationReopen: Bool {
        quickPanel.isVisibleOrOpening || isPresentingModal
    }

    private func applyChangedSettings(_ settings: AppSettings) {
        let previous = appliedSettings
        if previous?.appearance != settings.appearance {
            NSApp.appearance = settings.appearance.colorScheme.map(NSAppearance.init(named:)) ?? nil
        }
        if previous?.showDockIcon != settings.showDockIcon {
            NSApp.setActivationPolicy(settings.showDockIcon ? .regular : .accessory)
        }
        if previous?.shortcut != settings.shortcut {
            registerShortcut()
        }
        appliedSettings = settings
    }

    private static func dataRootURL() -> URL {
        #if DEBUG || QA
        if let customPath = ProcessInfo.processInfo.environment["CLIPPY_DATA_DIRECTORY"],
           !customPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: customPath, isDirectory: true).standardizedFileURL
        }
        #endif
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appending(path: "Clippy", directoryHint: .isDirectory)
    }

    private static var shouldMigrateLegacySandbox: Bool {
        guard Bundle.main.bundleIdentifier == "com.evpl.clippy" else { return false }
        #if DEBUG || QA
        if ProcessInfo.processInfo.environment["CLIPPY_DATA_DIRECTORY"] != nil {
            return false
        }
        #endif
        return true
    }
}

@MainActor
private final class ClippyQuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    static let collectionBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .transient,
        .ignoresCycle
    ]

    private var panel: NSPanel?
    private var previousApplication: NSRunningApplication?
    private var keyboardMonitor: Any?
    private var isOpening = false
    private var isDismissing = false

    var hasPreviousApplication: Bool {
        previousApplication?.isTerminated == false
    }

    var isVisibleOrOpening: Bool {
        isOpening || panel?.isVisible == true
    }

    func show(state: AppState, nearCursor: Bool) {
        let panel = panel ?? makePanel(state: state)
        self.panel = panel
        if panel.isVisible {
            hide()
            return
        }

        isOpening = true
        let currentPID = ProcessInfo.processInfo.processIdentifier
        #if DEBUG || QA
        let overrideBundleID = ProcessInfo.processInfo.environment["CLIPPY_QA_PASTE_TARGET_BUNDLE_ID"]
        let overrideApplication = overrideBundleID.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0).first
        }
        #else
        let overrideApplication: NSRunningApplication? = nil
        #endif
        if let overrideApplication, !overrideApplication.isTerminated {
            previousApplication = overrideApplication
        } else if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != currentPID {
            previousApplication = frontmost
        } else {
            previousApplication = nil
        }

        position(panel, nearCursor: nearCursor)
        installKeyboardMonitor(for: panel)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.isOpening = false
            NotificationCenter.default.post(name: .quickPanelDidOpen, object: nil)
        }
    }

    func hide() {
        guard let panel, panel.isVisible else {
            previousApplication = nil
            return
        }
        isDismissing = true
        panel.orderOut(nil)
        previousApplication = nil
        isDismissing = false
    }

    func completeSelection(
        pasteIntoPreviousApplication: Bool,
        pasteService: AutomaticPasteService,
        completion: ((AutomaticPasteOutcome) -> Void)? = nil
    ) {
        let target = previousApplication
        previousApplication = nil
        isDismissing = true
        panel?.orderOut(nil)
        isDismissing = false
        pasteService.restoreFocus(
            to: target,
            automaticallyPaste: pasteIntoPreviousApplication,
            completion: completion
        )
    }

    func shutdown() {
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        panel?.orderOut(nil)
    }

    private func makePanel(state: AppState) -> NSPanel {
        let panel = ClippyQuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 620),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clippy"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.level = .floating
        panel.collectionBehavior = Self.collectionBehavior
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickPanelView().environmentObject(state))
        return panel
    }

    private func installKeyboardMonitor(for panel: NSPanel) {
        guard keyboardMonitor == nil else { return }
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
               let index = Self.numericIndex(forKeyCode: event.keyCode) {
                NotificationCenter.default.post(name: .quickPanelSelectIndex, object: index)
                return nil
            }
            switch event.keyCode {
            case UInt16(kVK_UpArrow):
                NotificationCenter.default.post(name: .quickPanelMoveUp, object: nil)
                return nil
            case UInt16(kVK_DownArrow):
                NotificationCenter.default.post(name: .quickPanelMoveDown, object: nil)
                return nil
            case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
                NotificationCenter.default.post(name: .quickPanelConfirmSelection, object: nil)
                return nil
            case UInt16(kVK_Escape):
                self.hide()
                return nil
            default:
                return event
            }
        }
    }

    static func numericIndex(forKeyCode keyCode: UInt16) -> Int? {
        [
            UInt16(kVK_ANSI_1): 0,
            UInt16(kVK_ANSI_2): 1,
            UInt16(kVK_ANSI_3): 2,
            UInt16(kVK_ANSI_4): 3,
            UInt16(kVK_ANSI_5): 4,
            UInt16(kVK_ANSI_6): 5,
            UInt16(kVK_ANSI_7): 6,
            UInt16(kVK_ANSI_8): 7,
            UInt16(kVK_ANSI_9): 8
        ][keyCode]
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isOpening, !isDismissing, panel?.isVisible == true else { return }
        hide()
    }

    private func position(_ panel: NSPanel, nearCursor: Bool) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let width = max(360, min(640, visible.width - 32))
        let height = max(360, min(620, visible.height - 32))
        panel.setContentSize(NSSize(width: width, height: height))

        var origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.midY - panel.frame.height / 2
        )
        if nearCursor {
            let mouse = NSEvent.mouseLocation
            origin.x = min(max(mouse.x - panel.frame.width / 2, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(mouse.y - panel.frame.height - 16, visible.minY), visible.maxY - panel.frame.height)
        }
        panel.setFrameOrigin(origin)
    }
}

@MainActor
final class HistoryWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(state: AppState) {
        let window = window ?? makeWindow(state: state)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(state: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Clippy — Historique")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Clippy.HistoryWindow")
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: HistoryView().environmentObject(state))
        return window
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(state: AppState) {
        let window = window ?? makeWindow(state: state)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(state: AppState) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Clippy — Réglages")
        window.minSize = NSSize(width: 620, height: 520)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Clippy.SettingsWindow")
        window.center()
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView().environmentObject(state))
        return window
    }
}
