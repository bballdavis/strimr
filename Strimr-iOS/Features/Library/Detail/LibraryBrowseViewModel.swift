import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseViewModel {
    private struct FolderBreadcrumb: Identifiable, Equatable {
        let id: String
        let title: String
        let endpoint: PlexEndpoint
    }

    let library: Library
    var browseItems: [LibraryBrowseItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel
    var itemFilter: ((MediaDisplayItem) -> Bool)?
    private var folderStack: [FolderBreadcrumb] = []

    private var reachedEnd = false
    private var hasLoadedMeta = false
    private var nextPageStart = 0

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let settingsManager: SettingsManager

    init(library: Library, context: PlexAPIContext, settingsManager: SettingsManager) {
        self.library = library
        self.context = context
        self.settingsManager = settingsManager
        controls = LibraryBrowseControlsViewModel(context: context)
        controls.onSelectionChanged = { [weak self] in
            Task { await self?.refresh() }
        }
        controls.onDisplayTypeChanged = { [weak self] in
            guard let self else { return }
            folderStack = []
            Task { await self.refresh() }
        }
    }

    var canNavigateBack: Bool {
        !folderStack.isEmpty
    }

    func load() async {
        guard browseItems.isEmpty else { return }
        await fetch(reset: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false)
    }

    func enterFolder(_ folder: LibraryBrowseFolderItem) {
        guard let endpoint = PlexEndpoint(key: folder.key) else { return }
        folderStack.append(
            FolderBreadcrumb(
                id: folder.key,
                title: folder.title,
                endpoint: endpoint,
            ),
        )
        Task { await refresh() }
    }

    func navigateBack() {
        guard !folderStack.isEmpty else { return }
        folderStack.removeLast()
        Task { await refresh() }
    }

    func refresh() async {
        reachedEnd = false
        hasLoadedMeta = false
        nextPageStart = 0
        await fetch(reset: true)
    }

    private func fetch(reset: Bool) async {
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
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
            let start = reset ? 0 : nextPageStart
            let endpoint = resolvedEndpoint(sectionId: sectionId)
            let includeCollections = settingsManager.interface.displayCollections ? true : nil
            let includeMeta = !hasLoadedMeta
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: includeMeta,
            )

            let response = try await sectionRepository.getSectionBrowseItems(
                path: endpoint.path,
                queryItems: queryItems,
                pagination: PlexPagination(start: start, size: 20),
            )

            if includeMeta, let meta = response.mediaContainer.meta {
                controls.applyMeta(meta)
                hasLoadedMeta = true
            }

            let rawItems = (response.mediaContainer.metadata ?? [])
                .compactMap(mapBrowseItem)
            let newItems = filterBrowseItems(rawItems)
            let total = response.mediaContainer.totalSize ?? (start + rawItems.count)

            if reset {
                browseItems = newItems
                nextPageStart = rawItems.count
            } else {
                let existingIDs = Set(browseItems.map(\.id))
                let deduped = newItems.filter { !existingIDs.contains($0.id) }
                browseItems.append(contentsOf: deduped)
                nextPageStart = start + rawItems.count
            }

            reachedEnd = nextPageStart >= total || rawItems.isEmpty

            // Keep paging when a full server page is removed by client-side filters.
            if itemFilter != nil, !rawItems.isEmpty, newItems.isEmpty, !reachedEnd {
                await fetch(reset: false)
            }
        } catch {
            guard !isCancellation(error) else { return }
            if reset {
                if browseItems.isEmpty {
                    resetState(error: error.localizedDescription)
                } else {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resolvedEndpoint(sectionId: Int) -> PlexEndpoint {
        if let currentFolderEndpoint {
            return currentFolderEndpoint
        }
        if let selectedDisplayType = controls.selectedDisplayType,
           let endpoint = PlexEndpoint(key: selectedDisplayType.key)
        {
            return endpoint
        }

        let path = "/library/sections/\(sectionId)/all"
        let typeValue = defaultTypeQueryValue
        let queryItems = [URLQueryItem.make("type", typeValue)].compactMap(\.self)
        return PlexEndpoint(path: path, queryItems: queryItems)
    }

    private var currentFolderEndpoint: PlexEndpoint? {
        folderStack.last?.endpoint
    }

    private var defaultTypeQueryValue: String? {
        switch library.type {
        case .movie where !library.isNoneAgentLibrary:
            "1"
        case .show:
            "2"
        default:
            nil
        }
    }

    private func mapBrowseItem(_ metadata: PlexBrowseMetadata) -> LibraryBrowseItem? {
        switch metadata {
        case let .item(plexItem):
            guard let mediaItem = MediaDisplayItem(plexItem: plexItem) else { return nil }
            return .media(mediaItem)
        case let .folder(folder):
            return .folder(
                LibraryBrowseFolderItem(
                    id: folder.key,
                    key: folder.key,
                    title: folder.title,
                ),
            )
        }
    }

    private func filterBrowseItems(_ items: [LibraryBrowseItem]) -> [LibraryBrowseItem] {
        guard let itemFilter else { return items }
        return items.filter { item in
            switch item {
            case let .media(media):
                return itemFilter(media)
            case .folder:
                return true
            }
        }
    }

    private func resetState(error: String? = nil) {
        browseItems = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
        nextPageStart = 0
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}
