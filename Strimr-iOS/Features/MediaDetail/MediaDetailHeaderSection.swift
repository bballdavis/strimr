import Observation
import SwiftUI
import UIKit

struct MediaDetailHeaderSection: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlexAPIContext.self) private var context
    @Bindable var viewModel: MediaDetailViewModel
    @Binding var isSummaryExpanded: Bool
    let heroHeight: CGFloat
    let onPlay: (String, PlexItemType) -> Void
    let onPlayFromStart: (String, PlexItemType) -> Void
    let onShuffle: (String, PlexItemType) -> Void
    @State private var isShowingShowDownloadSheet = false
    @State private var tooltipRatingId: String?
    @State private var playButtonHeight: CGFloat = 56

    var body: some View {
        ZStack(alignment: .topLeading) {
            heroBackground

            VStack(alignment: .leading, spacing: 16) {
                Spacer().frame(height: heroHeight - 40)

                headerSection
                playButtonsRow
                secondaryButtonsRow
                badgesSection
                externalRatingsSection

                if let tagline = viewModel.media.tagline, !tagline.isEmpty {
                    Text(tagline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                if let summary = viewModel.media.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(isSummaryExpanded ? nil : 3)

                        Button(action: { isSummaryExpanded.toggle() }) {
                            Text(isSummaryExpanded ? "common.actions.showLess" : "common.actions.readMore")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .tint(.brandSecondary)
                        }
                        .tint(.accentColor)
                    }
                }

                genresSection

                if let studio = viewModel.media.studio {
                    metaRow(label: String(localized: "media.detail.studio"), value: studio)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let watchActionErrorMessage = viewModel.watchActionErrorMessage {
                    Label(watchActionErrorMessage, systemImage: "exclamationmark.octagon.fill")
                        .foregroundStyle(.red)
                }

                if viewModel.isLoading {
                    ProgressView("media.detail.updating")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $isShowingShowDownloadSheet) {
            NavigationStack {
                ShowDownloadSelectionSheet(
                    viewModel: viewModel,
                    onSubmitSelection: { episodeIDs in
                        for episodeID in episodeIDs {
                            await downloadManager.enqueueItem(ratingKey: episodeID, context: context)
                        }
                    },
                    statusForRatingKey: { ratingKey in
                        downloadManager.status(for: ratingKey)
                    },
                )
            }
        }

    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let titleLogoURL = viewModel.titleLogoURL {
                GeometryReader { proxy in
                    let targetWidth = min(max(proxy.size.width * 0.35, 160), 560)
                    HStack {
                        Spacer(minLength: 0)
                        AsyncImage(url: titleLogoURL) { phase in
                            switch phase {
                            case let .success(image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: targetWidth)
                                    .frame(maxHeight: 140)
                            case .empty:
                                ProgressView()
                                    .controlSize(.small)
                            case .failure:
                                titleText
                            @unknown default:
                                titleText
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 150)
            } else {
                titleText
            }

            if let secondary = viewModel.media.secondaryLabel {
                Text(secondary)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if let tertiary = viewModel.media.tertiaryLabel {
                Text(tertiary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var titleBannerSection: some View {
        Group {
            if let titleBannerURL = viewModel.titleBannerURL {
                AsyncImage(url: titleBannerURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 72)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    case .empty:
                        EmptyView()
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }

    private var titleText: some View {
        Text(viewModel.media.primaryLabel)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(.primary)
            .lineLimit(2)
    }

    private var badgesSection: some View {
        HStack(spacing: 8) {
            if let year = viewModel.yearText {
                badge(text: year)
            }

            if let runtime = viewModel.runtimeText {
                badge(text: runtime, systemImage: "clock")
            }

            if let contentRating = viewModel.media.contentRating {
                badge(text: contentRating)
            }
        }
    }

    private var externalRatingsSection: some View {
        Group {
            if !viewModel.externalRatings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(viewModel.externalRatings) { rating in
                            ratingBadge(for: rating)
                        }
                    }
                }
            }
        }
    }

    private func ratingBadge(for rating: MediaExternalRating) -> some View {
        let isPresented = Binding<Bool>(
            get: { tooltipRatingId == rating.id },
            set: { if !$0 { tooltipRatingId = nil } }
        )
        return Button {
            tooltipRatingId = tooltipRatingId == rating.id ? nil : rating.id
        } label: {
            HStack(spacing: 5) {
                ratingProviderIconView(rating)
                Text(rating.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented, arrowEdge: .bottom) {
            Text(fullProviderName(for: rating))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func ratingProviderIconView(_ rating: MediaExternalRating) -> some View {
        let assetName = ratingIconAssetName(rating)
        if UIImage(named: assetName) != nil {
            Image(assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        } else {
            Image(systemName: ratingProviderSFSymbol(rating))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    private func ratingIconAssetName(_ rating: MediaExternalRating) -> String {
        let norm = normalizedRatingProvider(rating.provider)
        // RT audience gets a distinct asset name (falls back to popcorn SF symbol)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "rating.rt.audience"
        }
        switch norm {
        case "imdb": return "rating.imdb"
        case "rottentomatoes", "rt": return "rating.rt"
        case "tmdb", "themoviedatabase", "themoviedb": return "rating.tmdb"
        default: return "rating.\(norm)"
        }
    }

    private func ratingProviderSFSymbol(_ rating: MediaExternalRating) -> String {
        let norm = normalizedRatingProvider(rating.provider)
        if (norm == "rottentomatoes" || norm == "rt") && rating.isAudience {
            return "popcorn.fill"
        }
        switch norm {
        case "imdb": return "star.fill"
        case "rottentomatoes", "rt": return "circle.dotted.circle"
        case "tmdb", "themoviedatabase", "themoviedb": return "movieclapper.fill"
        case "tvdb": return "tv.fill"
        default: return "chart.bar.fill"
        }
    }

    private func fullProviderName(for rating: MediaExternalRating) -> String {
        switch normalizedRatingProvider(rating.provider) {
        case "imdb": return "IMDb Score"
        case "rottentomatoes", "rt":
            return rating.isAudience ? "Rotten Tomatoes Audience Score" : "Rotten Tomatoes Critics Score"
        case "tmdb", "themoviedatabase", "themoviedb": return "The Movie Database (TMDB) Score"
        case "tvdb": return "TheTVDB Rating"
        default: return rating.provider
        }
    }

    private func normalizedRatingProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private var genresSection: some View {
        Group {
            if !viewModel.media.genres.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("media.detail.genres")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(viewModel.media.genres, id: \.self) { genre in
                                badge(text: genre)
                            }
                        }
                    }
                }
            }
        }
    }

    private var heroBackground: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if let heroURL = viewModel.heroImageURL {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                                .clipped()
                                .overlay(Color.black.opacity(0.2))
                                .mask(heroMask)
                        case .empty:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        case .failure:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        @unknown default:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        }
                    }
                } else {
                    Color.gray.opacity(0.12)
                        .frame(width: proxy.size.width, height: heroHeight)
                        .mask(heroMask)
                }
            }
            .frame(height: heroHeight)
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
        .ignoresSafeArea(edges: .horizontal)
    }

    private func badge(text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func metaRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
        }
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    private var secondaryButtonsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            watchToggleButton
            downloadButton
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
        .padding(.bottom, 2)
    }

    private var playButtonsRow: some View {
        HStack(spacing: 12) {
            playButton

            if viewModel.shouldShowPlayFromStartButton {
                playFromStartButton
            }
        }
    }

    private var playButton: some View {
        Button(action: handlePlay) {
            HStack(spacing: 12) {
                PlayProgressIcon(progress: viewModel.primaryActionProgress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.primaryActionTitle)
                        .fontWeight(.semibold)
                    if let detail = viewModel.primaryActionDetail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor)
            )
            .foregroundStyle(.white)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: PlayButtonHeightPreferenceKey.self, value: proxy.size.height)
                }
            )
        }
        .buttonStyle(.plain)
        .onPreferenceChange(PlayButtonHeightPreferenceKey.self) { value in
            guard value > 0 else { return }
            playButtonHeight = value
        }
    }

    private var playFromStartButton: some View {
        Button(action: handlePlayFromStart) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 52)
                .frame(height: playButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("media.detail.playFromStart"))
    }

    private var watchToggleButton: some View {
        VStack(spacing: 2) {
            Button {
                Task {
                    await viewModel.toggleWatchStatus()
                }
            } label: {
                if viewModel.isUpdatingWatchStatus {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: viewModel.watchActionIcon)
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 48, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || viewModel.isUpdatingWatchStatus)

            Text(watchActionLabel)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(width: 82, alignment: .center)
                .frame(minHeight: 28, alignment: .center)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var watchlistToggleButton: some View {
        VStack(spacing: 2) {
            Button {
                Task {
                    await viewModel.toggleWatchlistStatus()
                }
            } label: {
                if viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: viewModel.watchlistActionIcon)
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 48, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading || viewModel.isLoadingWatchlistStatus || viewModel.isUpdatingWatchlistStatus)

            Text(viewModel.watchlistActionTitle)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(width: 82, alignment: .center)
                .frame(minHeight: 28, alignment: .center)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var downloadButton: some View {
        VStack(spacing: 2) {
            Button {
                handleDownloadTap()
            } label: {
                if isDownloadInProgress {
                    ProgressView()
                        .tint(.brandSecondaryForeground)
                } else {
                    Image(systemName: downloadIconName)
                        .font(.headline.weight(.semibold))
                }
            }
            .foregroundStyle(Color.accentColor)
            .frame(width: 48, height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)

            Text("downloads.action")
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(width: 82, alignment: .center)
                .frame(minHeight: 28, alignment: .center)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var watchActionLabel: String {
        let unwatchedTitle = String(localized: "media.detail.watchAction.markUnwatched")
        if viewModel.watchActionTitle == unwatchedTitle {
            return "Mark as\nUnwatched"
        }
        return viewModel.watchActionTitle
    }

    private func handlePlay() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlay(ratingKey, playbackType)
        }
    }

    private func handlePlayFromStart() {
        Task {
            guard let ratingKey = await viewModel.playbackRatingKey() else { return }
            onPlayFromStart(ratingKey, playbackType)
        }
    }

    private func handleShuffle() {
        onShuffle(viewModel.media.id, viewModel.media.plexType)
    }

    private func handleDownloadTap() {
        switch viewModel.media.plexType {
        case .show:
            isShowingShowDownloadSheet = true
        case .season:
            Task {
                await downloadManager.enqueueSeason(ratingKey: viewModel.media.id, context: context)
            }
        case .movie, .episode, .clip:
            Task {
                await downloadManager.enqueueItem(ratingKey: viewModel.media.id, context: context)
            }
        case .collection, .playlist, .unknown:
            break
        }
    }

    private var downloadStatus: DownloadStatus? {
        downloadManager.status(for: viewModel.media.id)
    }

    private var isDownloadInProgress: Bool {
        downloadStatus == .queued || downloadStatus == .downloading
    }

    private var downloadIconName: String {
        switch downloadStatus {
        case .completed:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.circle"
        case .queued, .downloading:
            "arrow.down.circle.fill"
        case nil:
            "arrow.down.circle"
        }
    }

    private var playbackType: PlexItemType {
        viewModel.onDeckItem?.type ?? viewModel.media.plexType
    }
}

private struct PlayProgressIcon: View {
    let progress: Double?

    var body: some View {
        ZStack {
            if let progress {
                Circle()
                    .stroke(Color.brandSecondaryForeground.opacity(0.25), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        Color.brandSecondaryForeground,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round),
                    )
                    .rotationEffect(.degrees(-90))
            }

            Image(systemName: "play.fill")
                .font(.title3.weight(.semibold))
        }
        .frame(width: 30, height: 30)
    }
}

private struct PlayButtonHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 56

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
