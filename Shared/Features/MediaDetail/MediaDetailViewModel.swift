import Foundation
import Observation
import SwiftUI

struct MediaExternalRating: Identifiable, Hashable {
    let id: String
    let provider: String
    let value: String
    var isAudience: Bool = false
}

@MainActor
@Observable
final class MediaDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext

    var media: PlayableMediaItem
    var onDeckItem: MediaItem?
    var heroImageURL: URL?
    var titleLogoURL: URL?
    var titleBannerURL: URL?
    var externalRatings: [MediaExternalRating] = []
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []
    var seasons: [MediaItem] = []
    var episodes: [MediaItem] = []
    var cast: [CastMember] = []
    var relatedHubs: [Hub] = []
    var selectedSeasonId: String?
    var isLoadingSeasons = false
    var isLoadingEpisodes = false
    var isLoadingRelatedHubs = false
    var seasonsErrorMessage: String?
    var episodesErrorMessage: String?
    var relatedHubsErrorMessage: String?
    private var updatingWatchStatusIds: Set<String> = []
    var watchActionErrorMessage: String?
    var isLoadingWatchlistStatus = false
    var isUpdatingWatchlistStatus = false
    private var isWatchlisted = false

    init(media: PlayableMediaItem, context: PlexAPIContext) {
        self.media = media
        self.context = context
        resolveArtwork()
    }

    func loadDetails() async {
        cast = []
        relatedHubs = []
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.loadDetails")
            if media.type == .show {
                seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
            }
            relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
            return
        }

        isLoading = true
        errorMessage = nil
        onDeckItem = nil
        watchActionErrorMessage = nil

        do {
            let params = MetadataRepository.PlexMetadataParams(includeOnDeck: true)
            let response = try await metadataRepository.getMetadata(
                ratingKey: media.metadataRatingKey,
                params: params,
            )
            if let item = response.mediaContainer.metadata?.first,
               let playable = PlayableMediaItem(plexItem: item)
            {
                media = playable
                cast = castMembers(from: item)
                resolveBrandingAssets(from: item)
                resolveExternalRatings(from: item)
                resolveArtwork()
                resolveGradient()
            }
            onDeckItem = response.mediaContainer.metadata?.first?.onDeck?.metadata.map { MediaItem(plexItem: $0) }
            await loadWatchlistStatus()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        async let relatedHubsTask: Void = loadRelatedHubs()
        await loadSeasonsIfNeeded(forceReload: true)
        await relatedHubsTask
    }

    func loadSeasonsIfNeeded(forceReload: Bool = false) async {
        guard media.type == .show else { return }
        guard forceReload || seasons.isEmpty else { return }
        await fetchSeasons()
    }

    func selectSeason(id: String) async {
        guard selectedSeasonId != id else { return }
        selectedSeasonId = id
        episodes = []
        episodesErrorMessage = nil
        await fetchEpisodes(for: id)
    }

    func toggleWatchStatus(for target: MediaItem? = nil) async {
        let item = target ?? media.mediaItem

        guard let scrobbleRepository = try? ScrobbleRepository(context: context) else {
            if target == nil {
                watchActionErrorMessage = String(localized: "errors.selectServer.updateWatchStatus")
            }
            return
        }

        guard !isUpdatingWatchStatus(for: item) else { return }

        updatingWatchStatusIds.insert(item.id)
        if target == nil {
            watchActionErrorMessage = nil
        }
        defer { updatingWatchStatusIds.remove(item.id) }

        do {
            if isWatched(item) {
                try await scrobbleRepository.markUnwatched(key: item.id)
            } else {
                try await scrobbleRepository.markWatched(key: item.id)
            }
            await loadDetails()
        } catch {
            if target == nil {
                watchActionErrorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatchlistStatus() async {
        guard let discoverID = media.plexGuidID else { return }
        guard !isUpdatingWatchlistStatus else { return }
        guard let repository = try? DiscoverWatchlistRepository(context: context) else { return }

        isUpdatingWatchlistStatus = true
        defer { isUpdatingWatchlistStatus = false }

        do {
            if isWatchlisted {
                try await repository.removeFromWatchlist(ratingKey: discoverID)
            } else {
                try await repository.addToWatchlist(ratingKey: discoverID)
            }
            await loadWatchlistStatus()
        } catch {}
    }

    func imageURL(for media: MediaItem, width: Int = 320, height: Int = 180) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }

        let path = media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: width, height: height) }
    }

    private func resolveArtwork() {
        guard let imageRepository = try? ImageRepository(context: context) else {
            heroImageURL = nil
            return
        }

        heroImageURL = media.artPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.mediaItem.grandparentArtPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.mediaItem.parentThumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.thumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? titleBannerURL
        if titleBannerURL == nil {
            titleBannerURL = heroImageURL
        }
        resolveGradient()
    }

    private func resolveGradient() {
        backdropGradient = MediaBackdropGradient.colors(for: .playable(media.mediaItem))
    }

    private func loadWatchlistStatus() async {
        guard [.movie, .show].contains(media.type) else {
            isWatchlisted = false
            return
        }

        guard let discoverID = media.plexGuidID else {
            isWatchlisted = false
            return
        }

        guard let repository = try? DiscoverWatchlistRepository(context: context) else {
            isWatchlisted = false
            return
        }

        isLoadingWatchlistStatus = true
        defer { isLoadingWatchlistStatus = false }

        do {
            let response = try await repository.getUserState(discoverID: discoverID)
            let userState = response.mediaContainer.userState?.first
            isWatchlisted = userState?.watchlistedAt != nil
        } catch {
            isWatchlisted = false
        }
    }

    var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        return duration.mediaDurationText()
    }

    var yearText: String? {
        media.year.map(String.init)
    }

    var ratingText: String? {
        media.rating.map { String(format: "%.1f", $0) }
    }

    var selectedSeason: MediaItem? {
        seasons.first(where: { $0.id == selectedSeasonId })
    }

    var selectedSeasonTitle: String {
        selectedSeason?.title ?? String(localized: "media.detail.season")
    }

    func runtimeText(for item: MediaItem) -> String? {
        guard let duration = item.duration else { return nil }
        return duration.mediaDurationText()
    }

    func castImageURL(for member: CastMember, width: Int = 200, height: Int = 260) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = member.thumbPath else { return nil }
        return imageRepository.transcodeImageURL(path: thumbPath, width: width, height: height)
    }

    var primaryActionTitle: String {
        switch media.type {
        case .movie, .clip:
            hasProgress(for: media.mediaItem)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        case .show:
            hasProgress(for: onDeckItem)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        case .season, .episode:
            hasProgress(for: media.mediaItem)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        }
    }

    var primaryActionDetail: String? {
        switch media.type {
        case .movie, .clip:
            return timeLeftText(for: media.mediaItem)
        case .show:
            guard let onDeckItem else { return nil }
            let episodeLabel = seasonEpisodeLabel(for: onDeckItem)
            let timeLeft = timeLeftText(for: onDeckItem)
            if let timeLeft, let episodeLabel {
                return "\(episodeLabel) • \(timeLeft)"
            }
            return episodeLabel ?? timeLeft
        case .season, .episode:
            return timeLeftText(for: media.mediaItem)
        }
    }

    var primaryActionProgress: Double? {
        switch media.type {
        case .movie, .clip:
            return progressFraction(for: media.mediaItem)
        case .show:
            guard let onDeckItem else { return nil }
            return progressFraction(for: onDeckItem)
        case .season, .episode:
            return progressFraction(for: media.mediaItem)
        }
    }

    var shouldShowPlayFromStartButton: Bool {
        switch media.type {
        case .movie, .clip:
            hasProgress(for: media.mediaItem)
        case .show:
            hasProgress(for: onDeckItem)
        case .season, .episode:
            hasProgress(for: media.mediaItem)
        }
    }

    var primaryActionRatingKey: String? {
        switch media.type {
        case .movie, .clip:
            media.id
        case .show:
            onDeckItem?.id
        case .season, .episode:
            media.id
        }
    }

    var isWatched: Bool {
        isWatched(media.mediaItem)
    }

    func playbackRatingKey() async -> String? {
        primaryActionRatingKey
    }

    var watchActionTitle: String {
        watchActionTitle(for: media.mediaItem)
    }

    var watchActionIcon: String {
        watchActionIcon(for: media.mediaItem)
    }

    var watchlistActionTitle: String {
        isWatchlisted
            ? String(localized: "media.detail.watchlist.remove")
            : String(localized: "media.detail.watchlist.add")
    }

    var watchlistActionIcon: String {
        isWatchlisted ? "bookmark.fill" : "bookmark"
    }

    var shouldShowWatchlistButton: Bool {
        [.movie, .show].contains(media.type)
            && media.plexGuidID != nil
    }

    var isUpdatingWatchStatus: Bool {
        isUpdatingWatchStatus(for: media.mediaItem)
    }

    func isWatched(_ item: MediaItem) -> Bool {
        guard let playableType = PlayableItemType(plexType: item.type) else { return false }

        switch playableType {
        case .movie, .episode, .clip:
            return (item.viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount = item.leafCount, let viewedLeafCount = item.viewedLeafCount else {
                return false
            }
            guard leafCount > 0 else { return false }
            return leafCount == viewedLeafCount
        }
    }

    func watchActionTitle(for item: MediaItem) -> String {
        isWatched(item)
            ? String(localized: "media.detail.watchAction.markUnwatched")
            : String(localized: "media.detail.watchAction.markWatched")
    }

    func watchActionIcon(for item: MediaItem) -> String {
        isWatched(item) ? "checkmark.circle.fill" : "checkmark.circle"
    }

    func isUpdatingWatchStatus(for item: MediaItem) -> Bool {
        updatingWatchStatusIds.contains(item.id)
    }

    func progressFraction(for item: MediaItem) -> Double? {
        guard let percentage = item.viewProgressPercentage else { return nil }
        return min(1, max(0, percentage / 100))
    }

    private func hasProgress(for item: MediaItem?) -> Bool {
        guard let viewOffset = item?.viewOffset else { return false }
        return viewOffset > 0
    }

    private func timeLeftText(for item: MediaItem?) -> String? {
        guard
            let item,
            let duration = item.duration,
            let viewOffset = item.viewOffset,
            viewOffset > 0
        else {
            return nil
        }

        let remaining = max(0, duration - viewOffset)
        guard remaining > 0 else { return nil }

        return String(localized: "media.detail.timeLeft \(remaining.mediaDurationText())")
    }

    private func seasonEpisodeLabel(for item: MediaItem) -> String? {
        guard let season = item.parentIndex, let episode = item.index else { return nil }
        return String(localized: "media.detail.seasonEpisode \(season) \(episode)")
    }

    private func fetchSeasons() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
            return
        }

        isLoadingSeasons = true
        seasonsErrorMessage = nil
        episodesErrorMessage = nil
        defer { isLoadingSeasons = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: media.metadataRatingKey)
            let fetchedSeasons = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
            seasons = fetchedSeasons
            episodes = []

            guard !fetchedSeasons.isEmpty else {
                selectedSeasonId = nil
                episodes = []
                return
            }

            let nextSeasonId = selectedSeasonId ?? fetchedSeasons.first?.id
            selectedSeasonId = nextSeasonId

            if let seasonId = nextSeasonId {
                await fetchEpisodes(for: seasonId)
            } else {
                episodes = []
            }
        } catch {
            seasons = []
            selectedSeasonId = nil
            episodes = []
            seasonsErrorMessage = error.localizedDescription
        }
    }

    private func fetchEpisodes(for seasonId: String) async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            episodesErrorMessage = String(localized: "errors.selectServer.loadEpisodes")
            return
        }

        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: seasonId)
            let fetchedEpisodes = (response.mediaContainer.metadata ?? []).map(MediaItem.init)

            guard selectedSeasonId == seasonId else { return }
            episodes = fetchedEpisodes
        } catch {
            if selectedSeasonId == seasonId {
                episodes = []
                episodesErrorMessage = error.localizedDescription
            }
        }
    }

    private func castMembers(from item: PlexItem?) -> [CastMember] {
        guard let roles = item?.roles, !roles.isEmpty else { return [] }

        return roles.map { role in
            let identifier = role.id.map(String.init) ?? "\(role.tag)-\(role.role ?? "role")"
            let character = role.role?.isEmpty == false ? role.role : nil
            return CastMember(
                id: identifier,
                name: role.tag,
                character: character,
                thumbPath: role.thumb,
            )
        }
    }

    private func resolveBrandingAssets(from item: PlexItem) {
        let images = item.images ?? []
        guard let imageRepository = try? ImageRepository(context: context) else {
            titleLogoURL = nil
            titleBannerURL = nil
            return
        }

        titleLogoURL = images.first { image in
            image.type.localizedCaseInsensitiveContains("logo")
        }.flatMap { image in
            imageRepository.transcodeImageURL(path: image.url.path, width: 400, height: 200)
        }

        titleBannerURL = images.first { image in
            image.type.localizedCaseInsensitiveContains("banner")
        }.flatMap { image in
            imageRepository.transcodeImageURL(path: image.url.path, width: 800, height: 160)
        }
    }

    private func resolveExternalRatings(from item: PlexItem) {
        var ratingsByID: [String: MediaExternalRating] = [:]

        func addRating(provider: String, value: Double, isAudience: Bool) {
            guard isSupportedProvider(provider) else { return }
            let providerID = normalizedProvider(provider)
            let id = "\(providerID)-\(isAudience ? "audience" : "critic")"
            guard ratingsByID[id] == nil else { return }
            ratingsByID[id] = MediaExternalRating(
                id: id,
                provider: provider,
                value: formattedRatingValue(value, provider: provider),
                isAudience: isAudience
            )
        }

        for rating in item.ratings ?? [] {
            guard let value = rating.value else { continue }
            guard let provider = providerName(from: rating.image) ?? providerName(from: rating.type) else { continue }
            let isAudience = isAudienceRatingSource(rating.image) || isAudienceRatingSource(rating.type)
            addRating(provider: provider, value: value, isAudience: isAudience)
        }

        if let value = item.rating,
           let provider = providerName(from: item.ratingImage)
        {
            addRating(provider: provider, value: value, isAudience: false)
        }

        if let value = item.audienceRating,
           let provider = providerName(from: item.audienceRatingImage)
        {
            addRating(provider: provider, value: value, isAudience: true)
        }

        externalRatings = ratingsByID.values.sorted { lhs, rhs in
            let lhsPriority = ratingSortPriority(lhs)
            let rhsPriority = ratingSortPriority(rhs)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            if lhs.isAudience != rhs.isAudience { return lhs.isAudience == false }
            return lhs.provider < rhs.provider
        }
    }

    private func providerName(from imageIdentifier: String?) -> String? {
        guard let imageIdentifier else { return nil }
        let value = imageIdentifier.lowercased()
        if value.contains("imdb") { return "IMDb" }
        if value.contains("rotten") || value.contains("tomato") || value == "rt" { return "Rotten Tomatoes" }
        if value.contains("tvdb") || value.contains("thetvdb") { return "TVDB" }
        if value.contains("tmdb") || value.contains("themoviedb") { return "TMDB" }
        return nil
    }

    private func isAudienceRatingSource(_ source: String?) -> Bool {
        guard let source else { return false }
        let value = source.lowercased()
        return value.contains("audience") || value.contains("user") || value.contains("popcorn")
    }

    private func normalizedProvider(_ provider: String) -> String {
        provider
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
    }

    private func isSupportedProvider(_ provider: String) -> Bool {
        switch normalizedProvider(provider) {
        case "imdb", "rottentomatoes", "rt", "tmdb", "themoviedatabase", "themoviedb", "tvdb":
            return true
        default:
            return false
        }
    }

    private func ratingSortPriority(_ rating: MediaExternalRating) -> Int {
        let provider = normalizedProvider(rating.provider)
        switch provider {
        case "rottentomatoes", "rt": return rating.isAudience ? 1 : 0
        case "imdb": return 2
        case "tmdb", "themoviedatabase", "themoviedb": return 3
        case "tvdb": return 4
        default: return 9
        }
    }

    private func formattedRatingValue(_ rawValue: Double, provider: String) -> String {
        let providerID = normalizedProvider(provider)
        if providerID == "rottentomatoes" || providerID == "rt" {
            let percentage = rawValue <= 10 ? rawValue * 10 : rawValue
            return "\(Int(percentage.rounded()))%"
        }

        if providerID == "imdb" {
            return String(format: "%.1f", rawValue)
        }

        return String(format: "%.1f", rawValue)
    }

    func loadRelatedHubs() async {
        guard let hubRepository = try? HubRepository(context: context) else {
            relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
            return
        }

        isLoadingRelatedHubs = true
        relatedHubsErrorMessage = nil
        defer { isLoadingRelatedHubs = false }

        do {
            let response = try await hubRepository.getRelatedMediaHubs(ratingKey: media.metadataRatingKey)
            relatedHubs = (response.mediaContainer.hub ?? []).map(Hub.init)
        } catch {
            relatedHubs = []
            relatedHubsErrorMessage = error.localizedDescription
        }
    }
}
