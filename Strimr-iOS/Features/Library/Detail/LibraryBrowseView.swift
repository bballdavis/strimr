import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void
    var onLongPressMedia: (MediaDisplayItem) -> Void = { _ in }
    var topContent: AnyView? = nil
    var overrideLayout: MediaCarousel.Layout? = nil
    var showsControls: Bool = true

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var resolvedLayout: MediaCarousel.Layout {
        overrideLayout ?? .portrait
    }

    private var defaultCardWidth: CGFloat {
        resolvedLayout == .landscape ? 200 : 112
    }

    private var usesPhoneLandscapeGrid: Bool {
        resolvedLayout == .landscape && horizontalSizeClass == .compact
    }

    private var phoneLandscapeColumnCount: Int {
        verticalSizeClass == .compact ? 4 : 2
    }

    private func cardWidth(for availableWidth: CGFloat) -> CGFloat {
        guard usesPhoneLandscapeGrid else {
            return defaultCardWidth
        }

        let columns = CGFloat(phoneLandscapeColumnCount)
        let totalSpacing = 12 * (columns - 1)
        return floor((availableWidth - totalSpacing) / columns)
    }

    private func gridColumns(for availableWidth: CGFloat) -> [GridItem] {
        guard usesPhoneLandscapeGrid else {
            return [
                GridItem(.adaptive(minimum: defaultCardWidth, maximum: defaultCardWidth), spacing: 12, alignment: .top),
            ]
        }

        return Array(
            repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top),
            count: phoneLandscapeColumnCount
        )
    }

    var body: some View {
        @Bindable var controls = viewModel.controls

        GeometryReader { proxy in
            let gridWidth = max(proxy.size.width - 32, defaultCardWidth)
            let cardWidth = cardWidth(for: gridWidth)

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

                    LazyVGrid(columns: gridColumns(for: gridWidth), spacing: 16) {
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
