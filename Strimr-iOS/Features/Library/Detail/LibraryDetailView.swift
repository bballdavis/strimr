import SwiftUI
import PlinxCore
import OSLog

struct LibraryDetailView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Plinx", category: "LibraryDetailSafety")

    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.safetyPolicy) private var safetyPolicy
    @Environment(\.dismiss) private var dismiss
    let library: Library
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }

    @State private var selectedTab: LibraryDetailTab = .recommended

    private var scrollingTopContent: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 40, height: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Text(library.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                KidsLibraryTabPicker(tabs: availableTabs, selectedTab: $selectedTab)
                    .frame(height: 76)
            }
            .padding(.top, 4)
        )
    }

    var body: some View {
        Group {
            switch selectedTab {
            case .recommended:
                LibraryRecommendedView(
                    viewModel: makeRecommendedViewModel(),
                    onSelectMedia: onSelectMedia,
                    onLongPressMedia: onLongPressMedia,
                    topContent: scrollingTopContent,
                    overrideLayout: preferredCarouselLayout,
                )
            case .browse:
                LibraryBrowseView(
                    viewModel: makeBrowseViewModel(),
                    onSelectMedia: onSelectMedia,
                    onLongPressMedia: onLongPressMedia,
                    topContent: scrollingTopContent,
                    overrideLayout: preferredCarouselLayout,
                )
            case .collections:
                LibraryCollectionsView(
                    viewModel: makeCollectionsViewModel(),
                    onSelectMedia: onSelectMedia,
                    onLongPressMedia: onLongPressMedia,
                    topContent: scrollingTopContent,
                )
            case .playlists:
                LibraryPlaylistsView(
                    viewModel: LibraryPlaylistsViewModel(
                        library: library,
                        context: plexApiContext,
                    ),
                    onSelectMedia: onSelectMedia,
                    onLongPressMedia: onLongPressMedia,
                    topContent: scrollingTopContent,
                )
            }
        }
        .environment(\.preferredLandscapeArtworkKind, preferredLandscapeArtworkKind)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
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
    /// Movie and show libraries use portrait (poster) cards — UNLESS the library
    /// uses the "none" agent (e.g. YouTube, Home Videos), which have landscape content.
    /// All other library types (e.g. clips) also use landscape (letterbox).
    private var preferredCarouselLayout: MediaCarousel.Layout? {
        prefersLandscapeLibraryLayout ? .landscape : nil
    }

    private var preferredLandscapeArtworkKind: MediaImageViewModel.ArtworkKind? {
        guard prefersLandscapeLibraryLayout else { return nil }
        return .thumb
    }

    private var prefersLandscapeLibraryLayout: Bool {
        if library.isNoneAgentLibrary {
            return true
        }
        switch library.type {
        case .movie, .show:
            return false
        default:
            return true
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
              if (library.type == .movie || library.type == .show), case .collection = item {
                 return false
              }
              return StrimrAdapter.isAllowed(item, policy: policy)
        }
        return vm
    }

    private func makeCollectionsViewModel() -> LibraryCollectionsViewModel {
        let vm = LibraryCollectionsViewModel(library: library, context: plexApiContext)
        let policy = safetyPolicy
        vm.itemFilter = { item in
            StrimrAdapter.isAllowed(item, policy: policy)
        }
        return vm
    }

    private func filterRecommendedHub(_ hub: Hub, policy: SafetyPolicy) -> Hub? {
        guard let safetyFiltered = StrimrAdapter.filtered(hub, policy: policy) else {
            Self.logger.debug(
                "Drop hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) reason=safety_filter_empty"
            )
            return nil
        }
        if safetyFiltered.items.count != hub.items.count {
            Self.logger.debug(
                "Filtered hub id=\(hub.id, privacy: .public) title=\(hub.title, privacy: .public) before=\(hub.items.count) after=\(safetyFiltered.items.count)"
            )
        }
        return safetyFiltered
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
    private var buttonHeight: CGFloat    { isRegular ? 66 : 52 }
    private var iconPointSize: CGFloat   { isRegular ? 26 : 19 }
    private var labelFont: Font          { isRegular ? .subheadline : .caption }
    private var cornerRadius: CGFloat    { isRegular ? 16 : 12 }
    private var hSpacing: CGFloat        { isRegular ? 12 : 8 }
    private var iconLabelSpacing: CGFloat{ isRegular ? 8 : 5 }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: hSpacing) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .frame(minWidth: proxy.size.width - 32, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
        .frame(height: buttonHeight + 8)
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
