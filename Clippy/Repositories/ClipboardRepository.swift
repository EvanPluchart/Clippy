import Combine
import Foundation
@preconcurrency import SwiftData

@MainActor
final class ClipboardRepository: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var lastError: String?
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var pinnedCount = 0

    private let context: ModelContext
    private let fetchLimit: Int

    init(container: ModelContainer, fetchLimit: Int = 10_000) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        self.fetchLimit = fetchLimit
        reload()
    }

    func reload() {
        var descriptor = FetchDescriptor<ClipboardItem>()
        descriptor.fetchLimit = fetchLimit
        do {
            items = try context.fetch(descriptor)
            sortItems()
            refreshStatistics()
            lastError = nil
        } catch {
            lastError = "Impossible de lire l’historique."
            Log.storage.error("History fetch failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @discardableResult
    func record(_ capture: ClipboardCapture, storedImage: StoredImage?, policy: DuplicatePolicy) -> ClipboardItem? {
        let fingerprint = storedImage?.fingerprint ?? capture.fingerprint
        let duplicate: ClipboardItem?
        switch policy {
        case .keepAll: duplicate = nil
        case .consecutiveOnly: duplicate = items.first?.fingerprint == fingerprint ? items.first : nil
        case .mergeAll: duplicate = items.first(where: { $0.fingerprint == fingerprint })
        }
        if let duplicate {
            duplicate.lastUsedAt = .now
            duplicate.createdAt = .now
            guard save() else { return nil }
            sortItems()
            refreshStatistics()
            return nil
        }

        let item = ClipboardItem(type: capture.type, preview: capture.preview, content: capture.content,
                                 richTextData: capture.richTextData, relativeFilePath: storedImage?.imagePath,
                                 relativeThumbnailPath: storedImage?.thumbnailPath,
                                 estimatedSize: storedImage?.byteCount ?? capture.estimatedSize,
                                 sourceApplication: capture.sourceApplication,
                                 sourceBundleIdentifier: capture.sourceBundleIdentifier,
                                 fingerprint: fingerprint, imageWidth: storedImage?.width, imageHeight: storedImage?.height)
        context.insert(item)
        guard save() else { return nil }
        items.append(item)
        sortItems()
        refreshStatistics()
        return item
    }

    func markUsed(_ item: ClipboardItem) {
        item.lastUsedAt = .now
        item.useCount += 1
        guard save() else { return }
        sortItems()
    }

    func togglePinned(_ item: ClipboardItem) {
        item.isPinned.toggle()
        if save() { refreshStatistics() }
    }

    func setPinned(ids: Set<UUID>, pinned: Bool) {
        let targets = items.filter { ids.contains($0.id) && $0.isPinned != pinned }
        guard !targets.isEmpty else { return }
        targets.forEach { $0.isPinned = pinned }
        if save() { refreshStatistics() }
    }

    func delete(_ targets: [ClipboardItem]) -> [String] {
        guard !targets.isEmpty else { return [] }
        let ids = Set(targets.map(\.id))
        let paths = targets.flatMap { [$0.relativeFilePath, $0.relativeThumbnailPath].compactMap { $0 } }
        targets.forEach(context.delete)
        guard save() else { return [] }
        items.removeAll { ids.contains($0.id) }
        refreshStatistics()
        return paths
    }

    func delete(ids: Set<UUID>) -> [String] { delete(items.filter { ids.contains($0.id) }) }

    func clear(includePinned: Bool = false) -> [String] {
        delete(items.filter { includePinned || !$0.isPinned })
    }

    func retentionCandidates(settings: AppSettings, now: Date = .now) -> [ClipboardItem] {
        var victims = Set<UUID>()
        let unpinnedOldestFirst = items.filter { !$0.isPinned }.sorted { $0.lastUsedAt < $1.lastUsedAt }

        if settings.retentionPeriod.rawValue > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -settings.retentionPeriod.rawValue, to: now) {
            unpinnedOldestFirst.filter { $0.createdAt < cutoff }.forEach { victims.insert($0.id) }
        }

        var remaining = items.filter { !victims.contains($0.id) }
        if remaining.count > settings.maximumItemCount {
            let overflow = remaining.count - settings.maximumItemCount
            remaining.filter { !$0.isPinned }.sorted { $0.lastUsedAt < $1.lastUsedAt }.prefix(overflow).forEach { victims.insert($0.id) }
            remaining = items.filter { !victims.contains($0.id) }
        }

        let maximumBytes = Int64(settings.maximumStorageMegabytes) * 1_048_576
        var bytes = remaining.reduce(Int64(0)) { $0 + $1.estimatedSize }
        if bytes > maximumBytes {
            for item in remaining.filter({ !$0.isPinned }).sorted(by: { $0.lastUsedAt < $1.lastUsedAt }) where bytes > maximumBytes {
                victims.insert(item.id)
                bytes -= item.estimatedSize
            }
        }
        return items.filter { victims.contains($0.id) }
    }

    @discardableResult
    private func save() -> Bool {
        do {
            try context.save()
            lastError = nil
            return true
        } catch {
            context.rollback()
            reload()
            lastError = "Une opération n’a pas pu être enregistrée."
            Log.storage.error("Save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func sortItems() {
        items.sort {
            if $0.lastUsedAt == $1.lastUsedAt { return $0.createdAt > $1.createdAt }
            return $0.lastUsedAt > $1.lastUsedAt
        }
    }

    private func refreshStatistics() {
        totalBytes = items.reduce(0) { $0 + $1.estimatedSize }
        pinnedCount = items.lazy.filter(\.isPinned).count
    }
}
