import Observation
import SwiftUI

struct MediaDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: MainCoordinator
    @State var viewModel: MediaDetailViewModel
    @State private var isSummaryExpanded = false
    private let heroHeight: CGFloat = 320
    private let onPlay: (String, PlexItemType) -> Void
    private let onPlayFromStart: (String, PlexItemType) -> Void
    private let onShuffle: (String, PlexItemType) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void
    private let loadDetailsAction: (() async -> Void)?

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onShuffle: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        loadDetailsAction: (() async -> Void)? = nil,
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onShuffle = onShuffle
        self.onSelectMedia = onSelectMedia
        self.loadDetailsAction = loadDetailsAction
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MediaDetailHeaderSection(
                    viewModel: bindableViewModel,
                    isSummaryExpanded: $isSummaryExpanded,
                    heroHeight: heroHeight,
                    onPlay: onPlay,
                    onPlayFromStart: onPlayFromStart,
                    onShuffle: onShuffle,
                )

                if bindableViewModel.media.type == .show {
                    SeasonEpisodesSection(
                        viewModel: bindableViewModel,
                        onPlay: onPlay,
                        onShuffle: onShuffle,
                    )
                }

                CastSection(viewModel: bindableViewModel)

                RelatedHubsSection(
                    viewModel: bindableViewModel,
                    onSelectMedia: onSelectMedia,
                )
            }
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            detailHeader
        }
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let loadDetailsAction {
                await loadDetailsAction()
            } else {
                await bindableViewModel.loadDetails()
            }
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .background(gradientBackground(for: bindableViewModel))
    }

    private func gradientBackground(for viewModel: MediaDetailViewModel) -> some View {
        MediaBackdropGradient(colors: viewModel.backdropGradient)
            .ignoresSafeArea()
    }

    private var detailHeader: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 60, height: 60)
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
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }
}
