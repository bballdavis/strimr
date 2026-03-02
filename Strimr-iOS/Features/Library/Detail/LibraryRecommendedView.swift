import SwiftUI

struct LibraryRecommendedView: View {
    @State var viewModel: LibraryRecommendedViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var topContent: AnyView? = nil
    @Environment(SettingsManager.self) private var settingsManager

    /// When set, overrides the per-hub landscape-identifier logic and forces
    /// every carousel to use the specified layout. Useful when the consuming
    /// view already knows the library's content type (e.g. "other videos"
    /// libraries that should always show letterbox thumbnails).
    var overrideLayout: MediaCarousel.Layout? = nil

    private let landscapeHubIdentifiers: [String] = [
        "inprogress",
    ]

    private var visibleHubs: [Hub] {
        let hubs = viewModel.hubs
        guard !hubs.isEmpty else { return [] }

        let availableIds = hubs.map(\.id)
        let visibleIds = settingsManager.resolvedRecommendSectionIds(
            for: viewModel.library.id,
            availableSectionIds: availableIds
        )
        let hubById = Dictionary(uniqueKeysWithValues: hubs.map { ($0.id, $0) })
        return visibleIds.compactMap { hubById[$0] }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let topContent {
                    topContent
                }

                ForEach(visibleHubs) { hub in
                    if hub.hasItems {
                        MediaHubSection(title: hub.title) {
                            carousel(for: hub)
                        }
                    }
                }

                if viewModel.isLoading, !viewModel.hasContent {
                    ProgressView("library.recommended.loading")
                        .frame(maxWidth: .infinity)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if !viewModel.hasContent, !viewModel.isLoading {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func carousel(for hub: Hub) -> some View {
        if shouldUseLandscape(for: hub) {
            MediaCarousel(
                layout: .landscape,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
            )
        } else {
            MediaCarousel(
                layout: .portrait,
                items: hub.items,
                showsLabels: true,
                onSelectMedia: onSelectMedia,
                onLongPressMedia: onLongPressMedia,
            )
        }
    }

    private func shouldUseLandscape(for hub: Hub) -> Bool {
        if let override = overrideLayout { return override == .landscape }
        let identifier = hub.id.lowercased()
        return landscapeHubIdentifiers.contains { identifier.contains($0) }
    }
}
