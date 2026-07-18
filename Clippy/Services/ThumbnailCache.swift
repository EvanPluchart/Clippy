import AppKit
import Foundation

@MainActor
final class ThumbnailCache {
    private let cache = NSCache<NSString, NSImage>()

    init(maximumBytes: Int = 64 * 1_048_576, maximumCount: Int = 256) {
        cache.totalCostLimit = maximumBytes
        cache.countLimit = maximumCount
    }

    func image(relativePath: String, storage: ClipboardFileStorage) async -> NSImage? {
        let key = relativePath as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = await storage.data(relativePath: relativePath),
              let image = NSImage(data: data) else {
            return nil
        }
        let representation = image.representations.max {
            ($0.pixelsWide * $0.pixelsHigh) < ($1.pixelsWide * $1.pixelsHigh)
        }
        let decodedCost = max(
            data.count,
            (representation?.pixelsWide ?? 0) * (representation?.pixelsHigh ?? 0) * 4
        )
        cache.setObject(image, forKey: key, cost: decodedCost)
        return image
    }

    func remove(relativePaths: [String]) {
        relativePaths.forEach { cache.removeObject(forKey: $0 as NSString) }
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}
