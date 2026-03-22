import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LibraryBrowseViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Plinx", category: "LibraryBrowse")

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
    private var folderStack: [FolderBreadcrumb] = []

    private var reachedEnd = false
    private var hasLoadedMeta = false
    private var nextPageStart = 0

    /// Optional per-item filter applied after each page loads.
    /// Return `true` to keep an item. Defaults to `nil` (no filtering).
    var itemFilter: ((MediaDisplayItem) -> Bool)? = nil

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
        nextPageStart = 0
        browseItems = []
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
            var baseQueryItems = endpoint.queryItems
            if baseQueryItems.first(where: { $0.name == "type" }) == nil,
               let typeValue = defaultBrowseTypeQueryValue
            {
                baseQueryItems.append(URLQueryItem(name: "type", value: typeValue))
            }
            
            let includeMeta = !hasLoadedMeta
            let queryItems = controls.buildQueryItems(
                baseItems: baseQueryItems,
                includeCollections: settingsManager.interface.displayCollections,
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
            
            let newItems: [LibraryBrowseItem] = {
                if let filter = itemFilter {
                    return rawItems.filter { item in
                        switch item {
                        case .media(let media):
                            return filter(media)
                        case .folder:
                            return true
                        }
                    }
                }
                return rawItems
            }()

            let total = response.mediaContainer.totalSize ?? (start + rawItems.count)

            if reset {
                browseItems = newItems
                nextPageStart = rawItems.count
            } else {
                let existingIDs = Set(browseItems.map(\.id))
                let deduped = newItems.filter { !existingIDs.contains($0.id) }
                let duplicateCount = newItems.count - deduped.count
                if duplicateCount > 0 {
                    Self.logger.debug(
                        "Dedup browse append duplicates=\(duplicateCount, privacy: .public) start=\(start, privacy: .public) incoming=\(newItems.count, privacy: .public)"
                    )
                }
                browseItems.append(contentsOf: deduped)
                nextPageStart = start + rawItems.count
            }

            reachedEnd = nextPageStart >= total || rawItems.isEmpty
            Self.logger.debug(
                "Browse page loaded reset=\(reset, privacy: .public) start=\(start, privacy: .public) raw=\(rawItems.count, privacy: .public) kept=\(newItems.count, privacy: .public) totalItems=\(self.browseItems.count, privacy: .public) total=\(total, privacy: .public) reachedEnd=\(self.reachedEnd, privacy: .public)"
            )

            // Auto-advance pagination: when every item on this page was removed
            // by the client-side itemFilter (e.g. safety rating filter), fetch
            // the next page immediately so the UI never shows an empty state
            // while allowed content exists on later pages.
            if itemFilter != nil, !rawItems.isEmpty, newItems.isEmpty, !reachedEnd {
                await fetch(reset: false)
            }
        } catch {
            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
            Self.logger.error("Browse fetch failed reset=\(reset, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }
    }

    private func resolvedEndpoint(sectionId: Int) -> PlexEndpoint {
        if let currentFolderEndpoint {
            return currentFolderEndpoint
        }
        let path = "/library/sections/\(sectionId)/all"
        return PlexEndpoint(path: path, queryItems: [])
    }

    private var currentFolderEndpoint: PlexEndpoint? {
        folderStack.last?.endpoint
    }

    private var defaultBrowseTypeQueryValue: String? {
        switch library.type {
        case .movie where !library.isNoneAgentLibrary:
            return "1"
        case .show:
            return "2"
        default:
            return nil
        }
    }

    private func mapBrowseItem(_ metadata: PlexBrowseMetadata) -> LibraryBrowseItem? {
        switch metadata {
        case let .item(plexItem):
            guard let mediaItem = MediaDisplayItem(plexItem: plexItem) else { return nil }
            if (library.type == .movie || library.type == .show), case .collection = mediaItem {
                return nil
            }
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

    private func resetState(error: String? = nil) {
        browseItems = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
        nextPageStart = 0
    }
}
