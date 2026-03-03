import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LibraryCollectionsViewModel {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Strimr", category: "LibraryCollections")

    let library: Library
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    private var reachedEnd = false

    /// Optional per-item filter applied after each page loads.
    /// Return `true` to keep an item. Defaults to `nil` (no filtering).
    var itemFilter: ((MediaDisplayItem) -> Bool)? = nil

    @ObservationIgnored private let context: PlexAPIContext

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard items.isEmpty else { return }
        await fetch(reset: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false)
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
            let start = reset ? 0 : items.count
            let response = try await sectionRepository.getSectionCollections(
                sectionId: sectionId,
                includeCollections: true,
                pagination: PlexPagination(start: start, size: 20),
            )

            let rawItems = (response.mediaContainer.metadata ?? [])
                .compactMap(MediaDisplayItem.init)
            let newItems: [MediaDisplayItem] = {
                guard let filter = itemFilter else { return rawItems }
                return rawItems.filter(filter)
            }()
            let total = response.mediaContainer.totalSize ?? (start + rawItems.count)

            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

            reachedEnd = (start + rawItems.count) >= total || rawItems.isEmpty

            if rawItems.count != newItems.count {
                self.logger.debug(
                    "Filtered collections library=\(self.library.title, privacy: .public) before=\(rawItems.count) after=\(newItems.count) start=\(start)"
                )
            }
        } catch {
            if library.type == .movie || library.type == .show {
                logger.error(
                    "Collections fetch failed for movie/show library=\(self.library.title, privacy: .public) error=\(error.localizedDescription, privacy: .public); treating as empty"
                )
                if reset {
                    items = []
                }
                reachedEnd = true
                errorMessage = nil
                return
            }

            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }
}
