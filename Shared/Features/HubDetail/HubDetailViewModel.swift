import Foundation
import Observation

@MainActor
@Observable
final class HubDetailViewModel {
    let hub: Hub
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    @ObservationIgnored var itemFilter: ((MediaDisplayItem) -> Bool)?

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var reachedEnd = false
    @ObservationIgnored private var totalItemCount: Int?
    @ObservationIgnored private var rawLoadedCount = 0
    @ObservationIgnored private let pageSize = 50

    init(hub: Hub, context: PlexAPIContext) {
        self.hub = hub
        self.context = context
    }

    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await reload()
    }

    func reload() async {
        items = []
        reachedEnd = false
        totalItemCount = nil
        rawLoadedCount = 0
        await loadPage(start: 0, isInitialLoad: true)
    }

    func loadMoreIfNeeded(currentItem item: MediaDisplayItem) async {
        guard item.id == items.last?.id else { return }
        await loadMore()
    }

    func loadMore() async {
        guard !items.isEmpty else { return }
        await loadPage(start: rawLoadedCount, isInitialLoad: false)
    }

    private func loadPage(start: Int, isInitialLoad: Bool) async {
        guard !reachedEnd else { return }
        guard !isLoading, !isLoadingMore else { return }

        guard let repository = try? HubRepository(context: context) else {
            errorMessage = String(localized: "hub.error.loadFailed")
            return
        }

        guard let endpoint = PlexEndpoint(key: hub.key) else {
            errorMessage = String(localized: "hub.error.loadFailed")
            return
        }

        if isInitialLoad {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            if isInitialLoad {
                isLoading = false
            } else {
                isLoadingMore = false
            }
        }

        do {
            var newItems: [MediaDisplayItem] = []
            var nextStart = start

            repeat {
                let response = try await repository.getHubItems(
                    path: endpoint.path,
                    queryItems: endpoint.queryItems.filter { $0.name != "count" },
                    pagination: PlexPagination(start: nextStart, size: pageSize),
                )
                let rawMetadata = response.mediaContainer.metadata ?? []
                let mappedItems = rawMetadata
                    .filter(\.type.isSupported)
                    .compactMap(MediaDisplayItem.init)
                newItems = itemFilter.map { mappedItems.filter($0) } ?? mappedItems

                rawLoadedCount = nextStart + rawMetadata.count
                totalItemCount = response.mediaContainer.totalSize
                    ?? response.mediaContainer.size
                    ?? totalItemCount
                reachedEnd = rawMetadata.isEmpty
                    || totalItemCount.map { rawLoadedCount >= $0 } == true
                nextStart = rawLoadedCount
            } while itemFilter != nil && newItems.isEmpty && !reachedEnd

            if isInitialLoad {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "hub.error.loadFailed")
            if isInitialLoad {
                items = []
            }
        }
    }
}
