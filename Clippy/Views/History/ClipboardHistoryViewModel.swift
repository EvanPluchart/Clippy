import Combine
import Foundation

@MainActor
final class ClipboardHistoryViewModel: ObservableObject {
    enum SortOrder: String, CaseIterable, Identifiable {
        case recent, oldest, mostUsed
        var id: String { rawValue }
        var title: String { switch self { case .recent: "Plus récents"; case .oldest: "Plus anciens"; case .mostUsed: "Plus utilisés" } }
    }

    @Published var query = ""
    @Published var filter: ClipboardItemType?
    @Published var sortOrder = SortOrder.recent
    @Published var selection = Set<UUID>()
    @Published var displayLimit = 200
    @Published private(set) var debouncedQuery = ""

    private var subscriptions = Set<AnyCancellable>()

    init() {
        $query
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] value in self?.debouncedQuery = value }
            .store(in: &subscriptions)
    }

    func filtered(_ source: [ClipboardItem], limit: Int? = nil) -> [ClipboardItem] {
        let activeQuery = query.isEmpty ? "" : debouncedQuery
        var result = source.filter { item in
            (filter == nil || item.type == filter) &&
            (
                activeQuery.isEmpty ||
                item.preview.localizedCaseInsensitiveContains(activeQuery) ||
                (item.content?.localizedCaseInsensitiveContains(activeQuery) ?? false)
            )
        }
        switch sortOrder {
        case .recent: result.sort { $0.lastUsedAt > $1.lastUsedAt }
        case .oldest: result.sort { $0.lastUsedAt < $1.lastUsedAt }
        case .mostUsed:
            result.sort {
                $0.useCount == $1.useCount ? $0.lastUsedAt > $1.lastUsedAt : $0.useCount > $1.useCount
            }
        }
        return limit.map { Array(result.prefix($0)) } ?? result
    }

    func resetPagination() {
        displayLimit = 200
    }

    func loadMore() {
        displayLimit = min(displayLimit + 200, 10_000)
    }
}
