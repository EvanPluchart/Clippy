import Foundation
import SwiftData

enum ClipboardItemType: String, Codable, CaseIterable, Identifiable {
    case plainText, richText, image, url, file, color, unknown

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: "Texte"
        case .richText: "Texte enrichi"
        case .image: "Image"
        case .url: "Lien"
        case .file: "Fichier"
        case .color: "Couleur"
        case .unknown: "Autre"
        }
    }

    var symbol: String {
        switch self {
        case .plainText: "text.alignleft"
        case .richText: "textformat"
        case .image: "photo"
        case .url: "link"
        case .file: "doc"
        case .color: "paintpalette"
        case .unknown: "questionmark.square.dashed"
        }
    }
}

@Model
final class ClipboardItem {
    @Attribute(.unique) var id: UUID
    var typeRawValue: String
    var createdAt: Date
    var lastUsedAt: Date
    var preview: String
    var content: String?
    var richTextData: Data?
    var relativeFilePath: String?
    var relativeThumbnailPath: String?
    var estimatedSize: Int64
    var useCount: Int
    var isPinned: Bool
    var sourceApplication: String?
    var sourceBundleIdentifier: String?
    var fingerprint: String
    var imageWidth: Int?
    var imageHeight: Int?

    var type: ClipboardItemType {
        get { ClipboardItemType(rawValue: typeRawValue) ?? .unknown }
        set { typeRawValue = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        type: ClipboardItemType,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        preview: String,
        content: String? = nil,
        richTextData: Data? = nil,
        relativeFilePath: String? = nil,
        relativeThumbnailPath: String? = nil,
        estimatedSize: Int64,
        useCount: Int = 0,
        isPinned: Bool = false,
        sourceApplication: String? = nil,
        sourceBundleIdentifier: String? = nil,
        fingerprint: String,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) {
        self.id = id
        self.typeRawValue = type.rawValue
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.preview = preview
        self.content = content
        self.richTextData = richTextData
        self.relativeFilePath = relativeFilePath
        self.relativeThumbnailPath = relativeThumbnailPath
        self.estimatedSize = estimatedSize
        self.useCount = useCount
        self.isPinned = isPinned
        self.sourceApplication = sourceApplication
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.fingerprint = fingerprint
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }
}

struct ClipboardCapture {
    let type: ClipboardItemType
    let preview: String
    let content: String?
    let richTextData: Data?
    let imageData: Data?
    let estimatedSize: Int64
    let fingerprint: String
    let sourceApplication: String?
    let sourceBundleIdentifier: String?
}

struct StoredImage {
    let imagePath: String
    let thumbnailPath: String?
    let byteCount: Int64
    let width: Int
    let height: Int
    let fingerprint: String
}

struct OrphanCleanupResult {
    let removedFiles: Int
    let reclaimedBytes: Int64
}
