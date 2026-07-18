import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardMonitorService: ObservableObject {
    @Published private(set) var isRunning = false
    private let repository: ClipboardRepository
    private let settingsStore: SettingsStore
    private let storage: ClipboardFileStorage
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var workspaceCancellables = Set<AnyCancellable>()
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var suppressedChangeCount: Int?
    private var captureInProgress = false
    private var suspendedForSleep = false
    private var appliedMonitoringEnabled: Bool?
    private var appliedPollingInterval: Double?

    init(repository: ClipboardRepository, settingsStore: SettingsStore, storage: ClipboardFileStorage) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.storage = storage
        cancellable = settingsStore.$value.dropFirst().sink { [weak self] settings in
            Task { @MainActor [weak self] in
                self?.applySettings(enabled: settings.monitoringEnabled, interval: settings.pollingInterval)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        center.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.suspendForSleep() }
            }
            .store(in: &workspaceCancellables)
        center.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.resumeAfterWake() }
            }
            .store(in: &workspaceCancellables)
    }

    func start() {
        applySettings(enabled: settingsStore.value.monitoringEnabled, interval: settingsStore.value.pollingInterval)
    }

    func pause() { timer?.invalidate(); timer = nil; isRunning = false }

    func resume() {
        var settings = settingsStore.value
        settings.monitoringEnabled = true
        settingsStore.update(settings)
        applySettings(enabled: true, interval: settingsStore.value.pollingInterval, force: true)
    }

    func suppress(changeCount: Int) { suppressedChangeCount = changeCount; lastChangeCount = changeCount }

    private func applySettings(enabled: Bool, interval: Double, force: Bool = false) {
        let clampedInterval = min(max(interval, 0.3), 2.0)
        guard force ||
                appliedMonitoringEnabled != enabled ||
                appliedPollingInterval != clampedInterval else {
            return
        }
        appliedMonitoringEnabled = enabled
        appliedPollingInterval = clampedInterval
        timer?.invalidate()
        timer = nil
        guard enabled, !suspendedForSleep else {
            isRunning = false
            return
        }
        let timer = Timer(timeInterval: clampedInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        timer.tolerance = min(clampedInterval * 0.2, 0.2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let count = pasteboard.changeCount
        guard count != lastChangeCount, !captureInProgress else { return }
        lastChangeCount = count
        if let suppressedChangeCount {
            self.suppressedChangeCount = nil
            if suppressedChangeCount == count { return }
        }
        let settings = settingsStore.value
        guard let capture = autoreleasepool(invoking: {
            ClipboardParser.parse(pasteboard, settings: settings)
        }) else { return }
        captureInProgress = true
        Task {
            defer { captureInProgress = false }
            var stored: StoredImage?
            if let data = capture.imageData {
                let maximumBytes = settings.maximumImageMegabytes * 1_048_576
                do {
                    stored = try await storage.storeImage(data, maximumBytes: maximumBytes)
                } catch {
                    Log.storage.error("Image storage failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
            let inserted = repository.record(capture, storedImage: stored, policy: settings.duplicatePolicy)
            if inserted == nil, let stored {
                await storage.delete(relativePaths: [stored.imagePath, stored.thumbnailPath].compactMap { $0 })
            }
        }
    }

    private func suspendForSleep() {
        suspendedForSleep = true
        pause()
    }

    private func resumeAfterWake() {
        suspendedForSleep = false
        lastChangeCount = NSPasteboard.general.changeCount
        applySettings(
            enabled: settingsStore.value.monitoringEnabled,
            interval: settingsStore.value.pollingInterval,
            force: true
        )
    }
}
