import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ClipboardStorageError: LocalizedError {
    case imageTooLarge(maximumBytes: Int)
    case imageDimensionsTooLarge(maximumPixels: Int)

    var errorDescription: String? {
        switch self {
        case .imageTooLarge(let maximumBytes):
            "L’image normalisée dépasse la limite de \(Int64(maximumBytes).formattedBytes)."
        case .imageDimensionsTooLarge(let maximumPixels):
            "L’image dépasse la limite de \(maximumPixels.formatted()) pixels."
        }
    }
}

actor ClipboardFileStorage {
    private static let maximumPixelCount = 40_000_000
    private var recentlyCreatedPaths: [String: Date] = [:]

    let rootURL: URL
    let imagesURL: URL
    let thumbnailsURL: URL

    init(fileManager: FileManager = .default, rootURL customRootURL: URL? = nil) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = customRootURL ?? support.appending(path: "Clippy", directoryHint: .isDirectory)
        imagesURL = rootURL.appending(path: "images", directoryHint: .isDirectory)
        thumbnailsURL = rootURL.appending(path: "thumbnails", directoryHint: .isDirectory)
        do {
            try fileManager.createDirectory(at: imagesURL, withIntermediateDirectories: true)
            try fileManager.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        } catch {
            Log.storage.error("Storage directory creation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func storeImage(_ sourceData: Data, id: UUID = UUID(), maximumBytes: Int? = nil) throws -> StoredImage {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let rawImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let (pixelCount, overflow) = rawImage.width.multipliedReportingOverflow(by: rawImage.height)
        guard !overflow, pixelCount <= Self.maximumPixelCount else {
            throw ClipboardStorageError.imageDimensionsTooLarge(maximumPixels: Self.maximumPixelCount)
        }
        let fullSizeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(rawImage.width, rawImage.height),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        let image = CGImageSourceCreateThumbnailAtIndex(source, 0, fullSizeOptions as CFDictionary) ?? rawImage
        let imageName = "\(id.uuidString).png"
        let thumbnailName = "\(id.uuidString).jpg"
        let imageURL = imagesURL.appending(path: imageName)
        let thumbURL = thumbnailsURL.appending(path: thumbnailName)
        let temporaryImageURL = imagesURL.appending(path: ".\(imageName).tmp")
        let temporaryThumbURL = thumbnailsURL.appending(path: ".\(thumbnailName).tmp")

        defer {
            try? FileManager.default.removeItem(at: temporaryImageURL)
            try? FileManager.default.removeItem(at: temporaryThumbURL)
        }

        try write(image: image, to: temporaryImageURL, type: .png, properties: [:])
        let imageBytes = Int64(try temporaryImageURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? sourceData.count)
        if let maximumBytes, imageBytes > maximumBytes {
            throw ClipboardStorageError.imageTooLarge(maximumBytes: maximumBytes)
        }
        let fingerprint = try pixelFingerprint(image)

        let maxPixel = 320
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        var thumbnailPath: String?
        var thumbnailBytes: Int64 = 0
        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            do {
                try write(image: thumbnail, to: temporaryThumbURL, type: .jpeg,
                          properties: [kCGImageDestinationLossyCompressionQuality: 0.78])
                thumbnailBytes = Int64(try temporaryThumbURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
            } catch {
                thumbnailBytes = 0
                Log.storage.error("Thumbnail storage failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        try FileManager.default.moveItem(at: temporaryImageURL, to: imageURL)
        if thumbnailBytes > 0 {
            do {
                try FileManager.default.moveItem(at: temporaryThumbURL, to: thumbURL)
                thumbnailPath = "thumbnails/\(thumbnailName)"
            } catch {
                thumbnailBytes = 0
                Log.storage.error("Thumbnail finalization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let imagePath = "images/\(imageName)"
        recentlyCreatedPaths[imagePath] = .now
        if let thumbnailPath {
            recentlyCreatedPaths[thumbnailPath] = .now
        }
        return StoredImage(
            imagePath: imagePath,
            thumbnailPath: thumbnailPath,
            byteCount: imageBytes + thumbnailBytes,
            width: image.width,
            height: image.height,
            fingerprint: fingerprint
        )
    }

    func data(relativePath: String) -> Data? {
        guard let url = safeURL(relativePath: relativePath) else { return nil }
        return try? Data(contentsOf: url, options: [.mappedIfSafe])
    }

    func absoluteURL(relativePath: String) -> URL? { safeURL(relativePath: relativePath) }

    func delete(relativePaths: [String]) {
        for path in relativePaths {
            recentlyCreatedPaths.removeValue(forKey: path)
            guard let url = safeURL(relativePath: path) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeOrphans(
        referencedPaths: Set<String>,
        minimumAge: TimeInterval = 300,
        now: Date = .now
    ) -> OrphanCleanupResult {
        var removed = 0
        var reclaimedBytes: Int64 = 0
        for referencedPath in referencedPaths {
            recentlyCreatedPaths.removeValue(forKey: referencedPath)
        }
        for directory in [imagesURL, thumbnailsURL] {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files {
                let relative = directory.lastPathComponent + "/" + file.lastPathComponent
                if !referencedPaths.contains(relative) {
                    let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    if minimumAge > 0,
                       let createdAt = recentlyCreatedPaths[relative],
                       now.timeIntervalSince(createdAt) < minimumAge {
                        continue
                    }
                    do {
                        try FileManager.default.removeItem(at: file)
                        recentlyCreatedPaths.removeValue(forKey: relative)
                        removed += 1
                        reclaimedBytes += Int64(values?.fileSize ?? 0)
                    } catch {
                        Log.storage.error(
                            "Orphan removal failed: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
        }
        return OrphanCleanupResult(removedFiles: removed, reclaimedBytes: reclaimedBytes)
    }

    func eraseAllFiles() throws {
        recentlyCreatedPaths.removeAll()
        if FileManager.default.fileExists(atPath: imagesURL.path) {
            try FileManager.default.removeItem(at: imagesURL)
        }
        if FileManager.default.fileExists(atPath: thumbnailsURL.path) {
            try FileManager.default.removeItem(at: thumbnailsURL)
        }
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
    }

    private func write(image: CGImage, to url: URL, type: UTType, properties: [CFString: Any]) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func pixelFingerprint(_ image: CGImage) throws -> String {
        let bytesPerRow = image.width * 4
        var pixels = Data(count: bytesPerRow * image.height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: image.width,
                    height: image.height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                        CGBitmapInfo.byteOrder32Big.rawValue
                  ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { throw CocoaError(.fileReadCorruptFile) }

        var input = Data()
        input.reserveCapacity(32 + pixels.count)
        input.append(Data("rgba8-srgb:\(image.width)x\(image.height):".utf8))
        input.append(pixels)
        return ClipboardHash.data(input)
    }

    private func safeURL(relativePath: String) -> URL? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else { return nil }
        let root = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root
            .appending(path: relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            Log.storage.error("Rejected unsafe storage path")
            return nil
        }
        return candidate
    }
}
