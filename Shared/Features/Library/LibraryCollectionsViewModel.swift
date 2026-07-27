import Foundation
import Observation

@MainActor
@Observable
final class LibraryCollectionsViewModel {
    let library: Library
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    @ObservationIgnored var itemFilter: ((MediaDisplayItem) -> Bool)?
    private var reachedEnd = false
    private var rawLoadedCount = 0

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetch(reset: true, preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading || isLoadingMore) else { return }
        await fetch(reset: true, preservingExistingContent: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false, preservingExistingContent: false)
    }

    private func fetch(reset: Bool, preservingExistingContent: Bool) async {
        guard let sectionId = library.sectionId else {
            handleLoadError(
                String(localized: "errors.missingLibraryIdentifier"),
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.browseLibrary"),
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
            return
        }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            var nextStart = reset ? 0 : rawLoadedCount
            var newItems: [MediaDisplayItem] = []

            repeat {
                let response = try await sectionRepository.getSectionCollections(
                    sectionId: sectionId,
                    includeCollections: true,
                    pagination: PlexPagination(start: nextStart, size: 20),
                )

                let rawMetadata = response.mediaContainer.metadata ?? []
                let mappedItems = rawMetadata.compactMap(MediaDisplayItem.init)
                newItems = itemFilter.map { mappedItems.filter($0) } ?? mappedItems
                let total = response.mediaContainer.totalSize ?? (nextStart + rawMetadata.count)
                rawLoadedCount = nextStart + rawMetadata.count
                reachedEnd = rawLoadedCount >= total || rawMetadata.isEmpty
                nextStart = rawLoadedCount
            } while itemFilter != nil && newItems.isEmpty && !reachedEnd

            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }
        } catch {
            handleLoadError(
                error.localizedDescription,
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
        rawLoadedCount = 0
    }

    private func handleLoadError(_ message: String, reset: Bool, preservingExistingContent: Bool) {
        if preservingExistingContent, !items.isEmpty {
            errorMessage = nil
            isLoading = false
            isLoadingMore = false
        } else if reset {
            resetState(error: message)
        } else {
            errorMessage = message
            isLoadingMore = false
        }
    }
}
