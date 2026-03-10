import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var topContent: AnyView? = nil
    var overrideLayout: MediaCarousel.Layout? = nil
    var showsControls: Bool = true

    private var resolvedLayout: MediaCarousel.Layout {
        overrideLayout ?? .portrait
    }

    private var cardWidth: CGFloat {
        resolvedLayout == .landscape ? 200 : 112
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: cardWidth, maximum: cardWidth), spacing: 12, alignment: .top),
        ]
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let topContent {
                    topContent
                        .padding(.horizontal, 16)
                }

                if showsControls, controls.hasDisplayTypes {
                    LibraryBrowseControlsView(
                        viewModel: controls,
                        showsBackButton: viewModel.canNavigateBack,
                        onNavigateBack: viewModel.navigateBack,
                    )
                    .padding(.horizontal, 16)
                }

                LazyVGrid(columns: gridColumns, spacing: 16) {
                    ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
                        Group {
                            switch item {
                            case let .media(media):
                                if resolvedLayout == .landscape {
                                    LandscapeMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                                        onLongPressMedia(media)
                                    })
                                } else {
                                    PortraitMediaCard(media: media, width: cardWidth, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                    .simultaneousGesture(LongPressGesture().onEnded { _ in
                                        onLongPressMedia(media)
                                    })
                                }
                            case let .folder(folder):
                                FolderCard(title: folder.title, width: cardWidth, showsLabels: true) {
                                    viewModel.enterFolder(folder)
                                }
                            }
                        }
                        .task {
                            if index == viewModel.browseItems.count - 1 {
                                await viewModel.loadMore()
                            }
                        }
                    }

                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 16)
        }
        .overlay {
            if viewModel.isLoading, viewModel.browseItems.isEmpty {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.browseItems.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.browseItems.isEmpty {
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
