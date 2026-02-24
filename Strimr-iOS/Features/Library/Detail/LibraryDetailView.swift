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
            // Plinx: kid-friendly adaptive icon-button tab row instead of
            // the standard segmented control.
            KidsLibraryTabPicker(tabs: availableTabs, selectedTab: $selectedTab)
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
    }

    private var availableTabs: [LibraryDetailTab] {
        LibraryDetailTab.allCases.filter { tab in
            switch tab {
            case .playlists:
                // Plinx: playlists surface is hidden — not suitable for the
                // primary kid-facing library tab.
                false
            case .collections:
                settingsManager.interface.displayCollections
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

    /// SF Symbol name for the kid-friendly icon button tab bar.
    var iconName: String {
        switch self {
        case .recommended: return "star.fill"
        case .browse:      return "square.grid.2x2.fill"
        case .collections: return "rectangle.stack.fill"
        case .playlists:   return "music.note.list"
        }
    }
}

// MARK: - Kids Icon Tab Picker

/// Adaptive icon-button tab bar for library navigation.
///
/// Uses large buttons on iPad (`.regular` size class) and comfortably-sized but
/// smaller buttons on iPhone (`.compact` size class). The design intentionally
/// avoids the default segmented control in favour of large tap targets that are
/// easy for children to hit accurately.
private struct KidsLibraryTabPicker: View {
    let tabs: [LibraryDetailTab]
    @Binding var selectedTab: LibraryDetailTab

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isRegular: Bool { sizeClass == .regular }

    // Size tokens — compact (iPhone) vs regular (iPad)
    private var buttonMinWidth: CGFloat  { isRegular ? 108 : 82 }
    private var buttonHeight: CGFloat    { isRegular ? 72 : 56 }
    private var iconPointSize: CGFloat   { isRegular ? 26 : 19 }
    private var labelFont: Font          { isRegular ? .subheadline : .caption }
    private var cornerRadius: CGFloat    { isRegular ? 16 : 12 }
    private var hSpacing: CGFloat        { isRegular ? 14 : 10 }
    private var iconLabelSpacing: CGFloat{ isRegular ? 8 : 5 }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: hSpacing) {
                ForEach(tabs) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("library.detail.tabPicker")
    }

    private func tabButton(_ tab: LibraryDetailTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: iconLabelSpacing) {
                Image(systemName: tab.iconName)
                    .font(.system(size: iconPointSize, weight: .semibold))
                Text(tab.title)
                    .font(labelFont.bold())
                    .lineLimit(1)
            }
            .frame(minWidth: buttonMinWidth, minHeight: buttonHeight)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
            )
            .foregroundStyle(isSelected ? .white : .white.opacity(0.65))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isSelected)
        .accessibilityIdentifier("library.detail.tab.\(tab.rawValue)")
    }
}
