import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class HomeViewModel {
    var continueWatching: Hub?
    var recentlyAdded: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let libraryStore: LibraryStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Strimr", category: "Home")

    init(context: PlexAPIContext, settingsManager: SettingsManager, libraryStore: LibraryStore) {
        self.context = context
        self.settingsManager = settingsManager
        self.libraryStore = libraryStore
    }

    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || recentlyAdded.contains(where: \.hasItems)
    }

    func load() async {
        guard continueWatching == nil, recentlyAdded.isEmpty else { return }
        await reload()
    }

    func reload() async {
        loadTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await fetchHubs()
        }
        loadTask = task
        await task.value
    }

    private func fetchHubs() async {
        guard let hubRepository = try? HubRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.loadContent"))
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let hubParams: HubRepository.HubParams? = await {
                let hiddenLibraryIds = settingsManager.interface.hiddenLibraryIds
                guard !hiddenLibraryIds.isEmpty else { return nil }

                if libraryStore.libraries.isEmpty {
                    try? await libraryStore.loadLibraries()
                }

                let visibleSectionIds = libraryStore.libraries
                    .filter { !hiddenLibraryIds.contains($0.id) }
                    .compactMap(\.sectionId)

                return HubRepository.HubParams(sectionIds: visibleSectionIds)
            }()

            async let continueResponse = hubRepository.getContinueWatchingHub(params: hubParams)
            async let promotedResponse = hubRepository.getPromotedHub(
                params: hubParams,
                includeLibraryPlaylists: settingsManager.interface.displayPlaylists,
            )

            let continueHub = try await continueResponse.mediaContainer.hub?.first
            let promotedHubs = try await promotedResponse.mediaContainer.hub ?? []

            guard !Task.isCancelled else { return }

            continueWatching = continueHub.map(mapHub)
            recentlyAdded = promotedHubs.compactMap { hub in
                classifyRecentlyAddedHub(hub)
            }
        } catch {
            guard !Task.isCancelled else { return }
            ErrorReporter.capture(error)
            resetState(error: error.localizedDescription)
        }
    }

    private func classifyRecentlyAddedHub(_ hub: PlexHub) -> Hub? {
        guard hub.size > 0 else {
            logger.debug(
                "Exclude promoted hub id=\(hub.hubIdentifier, privacy: .public) title=\(hub.title, privacy: .public) reason=empty size=\(hub.size)"
            )
            return nil
        }

        let normalizedIdentifier = hub.hubIdentifier.lowercased()
        let normalizedTitle = hub.title.lowercased()

        if normalizedIdentifier.contains("recentlyadded") {
            logger.debug(
                "Include promoted hub id=\(hub.hubIdentifier, privacy: .public) title=\(hub.title, privacy: .public) reason=identifier_recentlyadded size=\(hub.size)"
            )
            return mapHub(hub)
        }

        if normalizedTitle.contains("recently") && normalizedTitle.contains("added") {
            logger.debug(
                "Include promoted hub id=\(hub.hubIdentifier, privacy: .public) title=\(hub.title, privacy: .public) reason=title_recently_added size=\(hub.size)"
            )
            return mapHub(hub)
        }

        let knownPromotedPatterns = [
            "recently.added",
            "recently_added",
            "recently-added",
            "home.recent",
            "clips.recent",
            "videos.recent",
        ]

        if knownPromotedPatterns.contains(where: normalizedIdentifier.contains) {
            logger.debug(
                "Include promoted hub id=\(hub.hubIdentifier, privacy: .public) title=\(hub.title, privacy: .public) reason=known_pattern size=\(hub.size)"
            )
            return mapHub(hub)
        }

        logger.debug(
            "Exclude promoted hub id=\(hub.hubIdentifier, privacy: .public) title=\(hub.title, privacy: .public) reason=no_recently_added_match size=\(hub.size)"
        )
        return nil
    }

    private func mapHub(_ hub: PlexHub) -> Hub {
        Hub(plexHub: hub)
    }

    private func resetState(error: String? = nil) {
        continueWatching = nil
        recentlyAdded = []
        errorMessage = error
        isLoading = false
    }
}
