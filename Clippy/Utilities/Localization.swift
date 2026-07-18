import Foundation

enum L10n {
    // Keep QA sample copy visible to the Release string extractor as well.
    static var qaSampleText: String {
        String(localized: "Une app macOS native, rapide et respectueuse de la vie privée.")
    }

    static var qaImagePreview: String {
        String(localized: "Aperçu de l’interface Clippy")
    }

    static var qaPreviewApplication: String {
        String(localized: "Aperçu")
    }

    static func itemCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "\(count) élément")
        }
        return String(localized: "\(count) éléments")
    }

    static func resultCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "\(count) résultat")
        }
        return String(localized: "\(count) résultats")
    }

    static func selectionCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "\(count) sélectionné")
        }
        return String(localized: "\(count) sélectionnés")
    }

    static func retentionPeriod(days: Int) -> String {
        if days == 1 {
            return String(localized: "\(days) jour")
        }
        return String(localized: "\(days) jours")
    }

    static func invalidExpressionCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "\(count) expression invalide sera ignorée.")
        }
        return String(localized: "\(count) expressions invalides seront ignorées.")
    }

    static func missingLegacyImageCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "\(count) ancienne image n’a pas pu être récupérée.")
        }
        return String(localized: "\(count) anciennes images n’ont pas pu être récupérées.")
    }

    static func textUsage(characterCount: Int, useCount: Int) -> String {
        let characters = characterCount == 1
            ? String(localized: "\(characterCount) caractère")
            : String(localized: "\(characterCount) caractères")
        let usage = useCount == 1
            ? String(localized: "utilisé une fois")
            : String(localized: "utilisé \(useCount) fois")
        return String(localized: "\(characters) · \(usage)")
    }

    static func monitoringSummary(itemCount count: Int, isRunning: Bool) -> String {
        let count = itemCount(count)
        if isRunning {
            return String(localized: "\(count) · Surveillance active")
        }
        return String(localized: "\(count) · Surveillance en pause")
    }

    static func cleanupSummary(
        date: String,
        removedItems: Int,
        reclaimedBytes: String
    ) -> String {
        let count = itemCount(removedItems)
        return String(
            localized: "Dernier nettoyage : \(date) · \(count) · \(reclaimedBytes) récupérés."
        )
    }
}
