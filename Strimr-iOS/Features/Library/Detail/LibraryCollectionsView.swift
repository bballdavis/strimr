import SwiftUI

struct LibraryCollectionsView: View {
    @State var viewModel: LibraryCollectionsViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var topContent: AnyView? = nil

    /// When `.landscape`, renders wider cells with LandscapeMediaCard instead
    /// of portrait cards. Used by Other Video libraries.
    var overrideLayout: MediaCarousel.Layout? = nil

    private var isLandscape: Bool { overrideLayout == .landscape }

    private var gridColumns: [GridItem] {
        if isLandscape {
            [GridItem(.adaptive(minimum: 190, maximum: 190), spacing: 12)]
        } else {
            [GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12)]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let topContent {
                    topContent
                }

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(viewModel.items) { media in
                        Group {
                            if isLandscape {
                                LandscapeMediaCard(media: media, width: 190, showsLabels: true) {
                                    onSelectMedia(media)
                                } onLongPress: {
                                    onLongPressMedia(media)
                                }
                            } else {
                                PortraitMediaCard(media: media, width: 112, showsLabels: true) {
                                    onSelectMedia(media)
                                } onLongPress: {
                                    onLongPressMedia(media)
                                }
                            }
                        }
                        .task {
                            if media == viewModel.items.last {
                                await viewModel.loadMore()
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.items.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.items.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.items.isEmpty {
                ContentUnavailableView(
                    "library.browse.empty.title",
                    systemImage: "square.grid.2x2.fill",
                    description: Text("library.browse.empty.description"),
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
