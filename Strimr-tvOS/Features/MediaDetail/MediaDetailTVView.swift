import Observation
import SwiftUI

struct MediaDetailTVView: View {
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(\.sharePlayPresentationPolicy) private var sharePlayPresentationPolicy
    @Environment(\.scenePhase) private var scenePhase
    @State var viewModel: MediaDetailViewModel
    @State private var focusedMedia: MediaItem?
    @State private var hasHandledInitialEpisodePosition = false
    @State private var hasUserSelectedSeason = false
    private let onPlay: (String, PlexItemType) -> Void
    private let onPlayFromStart: (String, PlexItemType) -> Void
    private let onShuffle: (String, PlexItemType) -> Void
    private let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onPlayFromStart: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onShuffle: @escaping (String, PlexItemType) -> Void = { _, _ in },
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onPlay = onPlay
        self.onPlayFromStart = onPlayFromStart
        self.onShuffle = onShuffle
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        GeometryReader { proxy in
            ZStack {
                MediaHeroBackgroundView(media: bindableViewModel.media.mediaItem)

                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        MediaHeroContentView(media: focusedMedia ?? bindableViewModel.media.mediaItem)
                            .frame(maxWidth: proxy.size.width * 0.60, alignment: .leading)

                        buttonsRow

                        if bindableViewModel.media.type == .show {
                            seasonsSection
                        }

                        CastSection(viewModel: bindableViewModel)
                        RelatedHubsSection(viewModel: bindableViewModel, onSelectMedia: onSelectMedia)
                    }
                }
            }
        }
        .task {
            await bindableViewModel.loadDetails()
        }
        .onChange(of: coordinator.isPresentingPlayer) { _, isPresenting in
            guard !isPresenting else { return }
            Task { await bindableViewModel.loadDetails() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onAppear {
            if focusedMedia == nil {
                focusedMedia = bindableViewModel.media.mediaItem
            }
            Task { await bindableViewModel.refreshIfNeeded() }
        }
        .onChange(of: bindableViewModel.media) { oldValue, newValue in
            if focusedMedia == nil || focusedMedia?.id == oldValue.id {
                focusedMedia = newValue.mediaItem
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .alert(
            "sharePlay.error.title",
            isPresented: Binding(
                get: { sharePlayCoordinator.errorMessage != nil },
                set: {
                    if !$0 {
                        sharePlayCoordinator.errorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {
                sharePlayCoordinator.errorMessage = nil
            }
        } message: {
            Text(sharePlayCoordinator.errorMessage ?? "")
        }
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)
        }
        .buttonStyle(MediaDetailActionStyle(treatment: .primary))
        .disabled(viewModel.primaryActionRatingKey == nil)
        .accessibilityIdentifier("media.detail.play")
    }

    private var buttonsRow: some View {
        HStack(spacing: 16) {
            playButton

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
            }

            if sharePlayPresentationPolicy == .enabled {
                sharePlayButton
            }

            watchToggleButton
        }
    }

    private var sharePlayButton: some View {
        Button {
            Task { await activateSharePlay() }
        } label: {
            Image(systemName: "shareplay")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(.accentColor)
        .accessibilityLabel(Text("sharePlay.action"))
        .accessibilityIdentifier("media.detail.shareplay")
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
        }
        .buttonStyle(
            MediaDetailActionStyle(
                treatment: .secondary,
                secondarySideLength: 70,
            ),
        )
        .accessibilityLabel(Text("media.detail.playFromStart"))
        .accessibilityIdentifier("media.detail.play-from-start")
    }

    private var watchToggleButton: some View {
        Button {
            Task {
                await viewModel.toggleWatchStatus()
            }
        } label: {
            if viewModel.isUpdatingWatchStatus {
                ProgressView()
                    .tint(.brandSecondaryForeground)
            } else {
                Image(systemName: "checkmark")
                    .font(.title2.weight(.semibold))
            }
        }
        .buttonStyle(
            MediaDetailActionStyle(
                treatment: .secondary,
                secondarySideLength: 68,
            ),
        )
        .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)
        .accessibilityIdentifier("media.detail.watch")
    }

    private var seasonsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            seasonSelector
            episodesRow
        }
    }

    @ViewBuilder
    private var seasonSelector: some View {
        if let error = viewModel.seasonsErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingSeasons || viewModel.isLoading, viewModel.seasons.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("media.detail.loadingSeasons")
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.seasons.isEmpty {
            Text("media.detail.noSeasons")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(viewModel.seasons) { season in
                        SeasonPillButton(
                            title: season.title,
                            isSelected: season.id == viewModel.selectedSeasonId,
                            onSelect: {
                                if season.id != viewModel.selectedSeasonId {
                                    hasUserSelectedSeason = true
                                }
                                Task { await viewModel.selectSeason(id: season.id) }
                            },
                            onFocus: {
                                focusedMedia = season
                            },
                            onBlur: {
                                if focusedMedia?.id == season.id {
                                    focusedMedia = nil
                                }
                            },
                        )
                    }
                }
                .padding(.vertical, 4)
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var episodesRow: some View {
        if let error = viewModel.episodesErrorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if viewModel.isLoadingEpisodes, viewModel.episodes.isEmpty {
            ProgressView("media.detail.loadingEpisodes")
        } else if viewModel.episodes.isEmpty {
            Text("media.detail.noEpisodes")
                .foregroundStyle(.secondary)
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 36) {
                        ForEach(viewModel.episodes) { episode in
                            EpisodeArtworkCard(
                                episode: episode,
                                imageURL: viewModel.imageURL(for: episode, width: 640, height: 360),
                                runtime: viewModel.runtimeText(for: episode),
                                progress: viewModel.progressFraction(for: episode),
                                width: 460,
                                onPlay: {
                                    onPlay(episode.id, .episode)
                                },
                                onFocus: {
                                    focusedMedia = episode
                                },
                            )
                            .id(episode.id)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.vertical, 4)
                }
                .task(id: viewModel.episodes.map(\.id)) {
                    await positionOnDeckEpisodeIfNeeded(using: scrollProxy)
                }
                .focusSection()
            }
        }
    }

    @MainActor
    private func positionOnDeckEpisodeIfNeeded(using scrollProxy: ScrollViewProxy) async {
        guard !hasHandledInitialEpisodePosition, !hasUserSelectedSeason else { return }
        hasHandledInitialEpisodePosition = true

        guard let primaryEpisodeID = viewModel.primaryActionItem?.id else { return }
        guard viewModel.episodes.contains(where: { $0.id == primaryEpisodeID }) else { return }

        await Task.yield()

        guard !Task.isCancelled else { return }
        guard !hasUserSelectedSeason else { return }
        guard viewModel.primaryActionItem?.id == primaryEpisodeID else { return }
        guard viewModel.episodes.contains(where: { $0.id == primaryEpisodeID }) else { return }

        scrollProxy.scrollTo(primaryEpisodeID, anchor: .leading)
    }

    private func handlePlay() {
        Task {
            guard
                let ratingKey = await viewModel.playbackRatingKey(),
                let playbackType = viewModel.primaryActionType
            else { return }

            if viewModel.shouldPlayPrimaryActionFromStart {
                onPlayFromStart(ratingKey, playbackType)
            } else {
                onPlay(ratingKey, playbackType)
            }
        }
    }

    private func handlePlayFromStart() {
        Task {
            guard
                let ratingKey = await viewModel.playbackRatingKey(),
                let playbackType = viewModel.primaryActionType
            else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private func activateSharePlay() async {
        guard
            let ratingKey = viewModel.primaryActionRatingKey,
            let playbackType = viewModel.primaryActionType,
            let item = viewModel.primaryActionItem
        else { return }
        await sharePlayCoordinator.activate(
            ratingKey: ratingKey,
            type: playbackType,
            title: item.primaryLabel,
            initialPosition: viewModel.primaryActionInitialPosition,
        )
    }
}

private struct SeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onFocus: () -> Void
    let onBlur: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .foregroundStyle(.brandSecondary)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? Color.brandSecondary.opacity(0.5) : Color.gray.opacity(0.12)),
                )
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(
                            isFocused ? Color.brandSecondary : Color.gray.opacity(0.25),
                            lineWidth: isFocused ? 3 : 1,
                        )
                }
        }
        .focusable()
        .focused($isFocused)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                onFocus()
            } else {
                onBlur()
            }
        }
        .onPlayPauseCommand(perform: onSelect)
        .onTapGesture(perform: onSelect)
    }
}

private struct EpisodeArtworkCard: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let width: CGFloat
    let onPlay: () -> Void
    let onFocus: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        EpisodeArtworkView(
            episode: episode,
            imageURL: imageURL,
            width: width,
            runtime: runtime,
            progress: progress,
        )
        .focusable()
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.12 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                onFocus()
            }
        }
        .onPlayPauseCommand(perform: onPlay)
        .onTapGesture(perform: onPlay)
    }
}
