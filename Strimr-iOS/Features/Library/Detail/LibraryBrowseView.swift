import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    /// When `.landscape`, renders wider cells with LandscapeMediaCard instead of
    /// portrait poster cards. Useful for libraries whose thumbnails are 16:9
    /// (e.g. home-video / clip libraries).
    var overrideLayout: MediaCarousel.Layout? = nil

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isLandscape: Bool { overrideLayout == .landscape }

    /// On iPhone (compact) with a landscape-type library, use a single full-width
    /// row per item. On iPad (regular), keep the adaptive multi-column grid.
    private var useSingleColumnList: Bool {
        isLandscape && sizeClass == .compact
    }

    private var gridColumns: [GridItem] {
        if isLandscape {
            return [GridItem(.adaptive(minimum: 190, maximum: 190), spacing: 12)]
        } else {
            return [GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12, alignment: .top)]
        }
    }

    var body: some View {
        // @Bindable var controls = viewModel.controls
        // (controls are hidden in Plinx — see comment below)

        GeometryReader { proxy in
            let singleColWidth = proxy.size.width - 32
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Plinx: The advanced sort/filter/folder controls are hidden
                    // because they expose complexity that isn't kid-appropriate
                    // (sorting by rating, folder browsing, display-type picker, etc).
                    // Re-enable behind a parental gate in a future settings screen.
                    //
                    // if controls.hasDisplayTypes {
                    //     LibraryBrowseControlsView(
                    //         viewModel: controls,
                    //         showsBackButton: viewModel.canNavigateBack,
                    //         onNavigateBack: viewModel.navigateBack
                    //     )
                    //     .padding(.horizontal, 16)
                    // }

                    if useSingleColumnList {
                        LazyVStack(spacing: 12) {
                            browseContent(width: singleColWidth)
                        }
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            browseContent(width: isLandscape ? 190 : 112)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
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

    @ViewBuilder
    private func browseContent(width: CGFloat) -> some View {
        ForEach(Array(viewModel.browseItems.enumerated()), id: \.element.id) { index, item in
            Group {
                switch item {
                case let .media(media):
                    if isLandscape {
                        LandscapeMediaCard(media: media, width: width, showsLabels: true) {
                            onSelectMedia(media)
                        }
                    } else {
                        PortraitMediaCard(media: media, width: width, showsLabels: true) {
                            onSelectMedia(media)
                        }
                    }
                case let .folder(folder):
                    FolderCard(title: folder.title, width: width, showsLabels: true) {
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
}
