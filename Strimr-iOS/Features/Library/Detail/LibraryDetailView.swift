import SwiftUI
import PlinxCore

struct LibraryDetailView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var selectedTab: LibraryDetailTab = .recommended

    var body: some View {
        VStack(spacing: 0) {
            Picker("library.detail.tabPicker", selection: $selectedTab) {
                ForEach(availableTabs) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Group {
                switch selectedTab {
                case .recommended:
                    LibraryRecommendedView(
                        viewModel: makeRecommendedViewModel(),
                        onSelectMedia: onSelectMedia,
                        overrideLayout: preferredCarouselLayout,
                    )
                case .browse:
                    LibraryBrowseView(
                        viewModel: makeBrowseViewModel(),
                        onSelectMedia: onSelectMedia,
                        overrideLayout: preferredCarouselLayout,
                    )
                case .collections:
                    LibraryCollectionsView(
                        viewModel: LibraryCollectionsViewModel(
                            library: library,
                            context: plexApiContext,
                        ),
                        onSelectMedia: onSelectMedia,
                    )
                case .playlists:
                    LibraryPlaylistsView(
                        viewModel: LibraryPlaylistsViewModel(
                            library: library,
                            context: plexApiContext,
                        ),
                        onSelectMedia: onSelectMedia,
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(library.title)
        .toolbarTitleDisplayMode(.inline)
        .onChange(of: settingsManager.interface.displayCollections) { _, displayCollections in
            if !displayCollections, selectedTab == .collections {
                selectedTab = .recommended
            }
        }
        .onChange(of: settingsManager.interface.displayPlaylists) { _, displayPlaylists in
            if !displayPlaylists, selectedTab == .playlists {
                selectedTab = .recommended
            }
        }
    }

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.allCases.filter { tab in
            switch tab {
            case .collections:
                settingsManager.interface.displayCollections
            case .playlists:
                settingsManager.interface.displayPlaylists
            default:
                true
            }
        }
    }

    /// Determines the carousel layout for this library's content.
    /// Movie and show libraries use portrait (poster) cards.
    /// All other library types (e.g. home videos, clips) use landscape (letterbox).
    private var preferredCarouselLayout: MediaCarousel.Layout? {
        switch library.type {
        case .movie, .show: return nil          // let hub-level heuristic decide
        default:            return .landscape   // letterbox for other video types
        }
    }

    private func makeRecommendedViewModel() -> LibraryRecommendedViewModel {
        let vm = LibraryRecommendedViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.hubFilter = { filterRecommendedHub($0, policy: policy) }
        return vm
    }

    private func makeBrowseViewModel() -> LibraryBrowseViewModel {
        let vm = LibraryBrowseViewModel(library: library, context: plexApiContext, settingsManager: settingsManager)
        let policy = safetyPolicy
        vm.itemFilter = { item in
            isAllowedInLibraryContext(item, policy: policy)
        }
        return vm
    }

    private var excludesCollectionsInBrowseContext: Bool {
        switch library.type {
        case .movie, .show:
            true
        default:
            false
        }
    }

    private func isAllowedInLibraryContext(_ item: MediaDisplayItem, policy: SafetyPolicy) -> Bool {
        if excludesCollectionsInBrowseContext, case .collection = item {
            return false
        }
        return StrimrAdapter.isAllowed(item, policy: policy)
    }

    private func filterRecommendedHub(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        guard let safetyFiltered = StrimrAdapter.filtered(hub, policy: policy) else {
            return nil
        }
        let contextFilteredItems = safetyFiltered.items.filter { item in
            isAllowedInLibraryContext(item, policy: policy)
        }
        guard !contextFilteredItems.isEmpty else {
            return nil
        }
        return Hub(id: safetyFiltered.id, title: safetyFiltered.title, items: contextFilteredItems)
    }
}

enum LibraryDetailTab: String, CaseIterable, Identifiable {
    case recommended
    case browse
    case collections
    case playlists

    var id: String {
        rawValue
    }

    var title: LocalizedStringKey {
        switch self {
        case .recommended:
            "library.detail.tab.recommended"
        case .browse:
            "library.detail.tab.browse"
        case .collections:
            "library.detail.tab.collections"
        case .playlists:
            "library.detail.tab.playlists"
        }
    }
}
