import Combine
import Foundation

struct CleanupSummary: Codable {
    let date: Date
    let removedItems: Int
    let removedOrphanFiles: Int
    let reclaimedBytes: Int64
}

@MainActor
final class ClipboardCleanupService: ObservableObject {
    @Published private(set) var lastSummary: CleanupSummary?
    @Published private(set) var isRunning = false

    private let repository: ClipboardRepository
    private let settingsStore: SettingsStore
    private let storage: ClipboardFileStorage
    private var timer: Timer?
    private let summaryKey = "Clippy.LastCleanupSummary"

    init(repository: ClipboardRepository, settingsStore: SettingsStore, storage: ClipboardFileStorage) {
        self.repository = repository
        self.settingsStore = settingsStore
        self.storage = storage
        if let data = UserDefaults.standard.data(forKey: summaryKey) {
            lastSummary = try? JSONDecoder().decode(CleanupSummary.self, from: data)
        }
    }

    func start() {
        guard timer == nil else { return }
        Task { await run() }
        let timer = Timer(timeInterval: 86_400, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.run() }
        }
        timer.tolerance = 3_600
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let candidates = repository.retentionCandidates(settings: settingsStore.value)
        let candidateSizes = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.estimatedSize) })
        let candidateIDs = Set(candidateSizes.keys)
        let paths = repository.delete(candidates)
        await storage.delete(relativePaths: paths)
        let remainingIDs = Set(repository.items.map(\.id))
        let deletedIDs = candidateIDs.subtracting(remainingIDs)
        let reclaimedItems = deletedIDs.reduce(Int64(0)) { $0 + (candidateSizes[$1] ?? 0) }
        let referenced = Set(repository.items.flatMap { [$0.relativeFilePath, $0.relativeThumbnailPath].compactMap { $0 } })
        let orphans = await storage.removeOrphans(referencedPaths: referenced)
        let summary = CleanupSummary(
            date: .now,
            removedItems: deletedIDs.count,
            removedOrphanFiles: orphans.removedFiles,
            reclaimedBytes: reclaimedItems + orphans.reclaimedBytes
        )
        lastSummary = summary
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: summaryKey)
        }
    }
}
