import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseViewModel {
    struct SectionCharacter: Identifiable, Hashable {
        let id: String
        let title: String
        let size: Int
        let startIndex: Int
    }

    private struct FolderBreadcrumb: Identifiable, Equatable {
        let id: String
        let title: String
        let endpoint: PlexEndpoint
    }

    let library: Library
    var itemsByIndex: [Int: LibraryBrowseItem] = [:]
    var totalItemCount = 0
    var sectionCharacters: [SectionCharacter] = []
    var isLoading = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel
    @ObservationIgnored var itemFilter: ((MediaDisplayItem) -> Bool)?

    private var loadedPageStarts: Set<Int> = []
    private var loadingPageStarts: Set<Int> = []
    private var folderStack: [FolderBreadcrumb] = []
    private var hasLoadedMeta = false
    private var rawLoadedCount = 0
    private var reachedEnd = false
    private var isLoadingFilteredPage = false

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let settingsManager: SettingsManager
    private let pageSize = 40

    init(
        library: Library,
        context: PlexAPIContext,
        settingsManager: SettingsManager,
    ) {
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

    var showsCharacterColumn: Bool {
        itemFilter == nil && supportsSectionCharacters && !sectionCharacters.isEmpty
    }

    func load() async {
        guard itemsByIndex.isEmpty else { return }
        await refresh()
    }

    func loadPagesAround(index: Int) async {
        guard index >= 0 else { return }
        if itemFilter != nil {
            if index >= max(totalItemCount - 8, 0) {
                await loadFilteredNextPage()
            }
            return
        }

        let pageStart = max(0, (index / pageSize) * pageSize)
        if itemsByIndex[index] == nil,
           loadedPageStarts.contains(pageStart),
           !loadingPageStarts.contains(pageStart)
        {
            loadedPageStarts.remove(pageStart)
        }
        let pageStarts = [
            pageStart - (pageSize * 2),
            pageStart - pageSize,
            pageStart,
            pageStart + pageSize,
            pageStart + (pageSize * 2),
        ]
        for start in pageStarts where start >= 0 && (totalItemCount == 0 || start < totalItemCount) {
            await loadPage(start: start)
        }
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
        resetState()
        isLoading = true
        defer { isLoading = false }
        if itemFilter != nil {
            await loadFilteredNextPage()
        } else {
            await loadPage(start: 0)
            await fetchCharactersIfNeeded()
        }
    }

    private func fetchCharactersIfNeeded() async {
        guard itemFilter == nil else { return }
        guard sectionCharacters.isEmpty else { return }
        guard supportsSectionCharacters else { return }
        guard let sectionId = library.sectionId else { return }
        guard let sectionRepository = try? SectionRepository(context: context) else { return }

        do {
            let endpoint = resolvedEndpoint(sectionId: sectionId)
            guard let firstCharacterEndpoint = firstCharacterEndpoint(from: endpoint) else { return }
            let includeCollections = includeCollectionsForBrowse
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: false,
            )

            let response = try await sectionRepository.getSectionFirstCharacters(
                path: firstCharacterEndpoint.path,
                queryItems: queryItems,
            )
            let directories = response.mediaContainer.directory ?? []
            var runningIndex = 0
            var characters: [SectionCharacter] = []

            for directory in directories {
                let size = max(0, directory.size ?? 0)
                guard size > 0 else { continue }
                let title = directory.title ?? directory.key ?? "#"
                let identifier = "\(title)-\(runningIndex)"
                characters.append(
                    SectionCharacter(
                        id: identifier,
                        title: title,
                        size: size,
                        startIndex: runningIndex,
                    ),
                )
                runningIndex += size
            }

            sectionCharacters = characters
            totalItemCount = max(totalItemCount, runningIndex)
        } catch {
            if itemsByIndex.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPage(start: Int) async {
        guard !loadedPageStarts.contains(start), !loadingPageStarts.contains(start) else { return }
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
            return
        }

        errorMessage = nil
        loadingPageStarts.insert(start)
        defer {
            loadingPageStarts.remove(start)
        }

        do {
            let endpoint = resolvedEndpoint(sectionId: sectionId)
            let includeCollections = includeCollectionsForBrowse
            let includeMeta = !hasLoadedMeta
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: includeMeta,
            )

            let response = try await sectionRepository.getSectionBrowseItems(
                path: endpoint.path,
                queryItems: queryItems,
                pagination: PlexPagination(start: start, size: pageSize),
            )

            if includeMeta, let meta = response.mediaContainer.meta {
                controls.applyMeta(meta)
                hasLoadedMeta = true
            }

            let newItems = (response.mediaContainer.metadata ?? [])
                .compactMap(mapBrowseItem)
            let total = response.mediaContainer.totalSize ?? (start + newItems.count)

            for (offset, item) in newItems.enumerated() {
                itemsByIndex[start + offset] = item
            }
            loadedPageStarts.insert(start)
            totalItemCount = max(totalItemCount, total)
        } catch {
            errorMessage = error.localizedDescription
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

    private var includeCollectionsForBrowse: Bool? {
        if library.isNoneAgentLibrary {
            return settingsManager.interface.displayCollections ? true : nil
        }
        switch library.type {
        case .movie, .show:
            return false
        default:
            return settingsManager.interface.displayCollections ? true : nil
        }
    }

    private func loadFilteredNextPage() async {
        guard !reachedEnd, !isLoadingFilteredPage else { return }
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
            return
        }

        errorMessage = nil
        isLoadingFilteredPage = true
        defer { isLoadingFilteredPage = false }

        do {
            while !reachedEnd {
                let endpoint = resolvedEndpoint(sectionId: sectionId)
                let includeMeta = !hasLoadedMeta
                let queryItems = controls.buildQueryItems(
                    baseItems: endpoint.queryItems,
                    includeCollections: includeCollectionsForBrowse,
                    includeMeta: includeMeta,
                )
                let response = try await sectionRepository.getSectionBrowseItems(
                    path: endpoint.path,
                    queryItems: queryItems,
                    pagination: PlexPagination(start: rawLoadedCount, size: pageSize),
                )

                if includeMeta, let meta = response.mediaContainer.meta {
                    controls.applyMeta(meta)
                    hasLoadedMeta = true
                }

                let rawMetadata = response.mediaContainer.metadata ?? []
                let rawItems = rawMetadata.compactMap(mapBrowseItem)
                let filteredItems = filteredBrowseItems(rawItems)
                let total = response.mediaContainer.totalSize ?? (rawLoadedCount + rawMetadata.count)
                rawLoadedCount += rawMetadata.count
                reachedEnd = rawLoadedCount >= total || rawMetadata.isEmpty

                let displayStart = itemsByIndex.count
                for (offset, item) in filteredItems.enumerated() {
                    itemsByIndex[displayStart + offset] = item
                }
                totalItemCount = itemsByIndex.count

                if !filteredItems.isEmpty || reachedEnd {
                    break
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func filteredBrowseItems(_ items: [LibraryBrowseItem]) -> [LibraryBrowseItem] {
        guard let itemFilter else { return items }
        return items.filter { item in
            switch item {
            case .folder:
                true
            case let .media(media):
                itemFilter(media)
            }
        }
    }

    private func firstCharacterEndpoint(from endpoint: PlexEndpoint) -> PlexEndpoint? {
        let components = endpoint.path.split(separator: "/")
        guard components.last == "all" else { return nil }
        let prefix = components.dropLast().joined(separator: "/")
        let path = "/\(prefix)/firstCharacter"
        return PlexEndpoint(path: path, queryItems: endpoint.queryItems)
    }

    private var supportsSectionCharacters: Bool {
        guard let sectionId = library.sectionId else { return false }
        let endpoint = resolvedEndpoint(sectionId: sectionId)
        return firstCharacterEndpoint(from: endpoint) != nil
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

    private func resetState(error: String? = nil) {
        itemsByIndex = [:]
        totalItemCount = 0
        sectionCharacters = []
        errorMessage = error
        isLoading = false
        loadedPageStarts = []
        loadingPageStarts = []
        hasLoadedMeta = false
        rawLoadedCount = 0
        reachedEnd = false
        isLoadingFilteredPage = false
    }
}
