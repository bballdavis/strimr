import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey = "strimr.settings"

    private(set) var settings: AppSettings

    init(userDefaults: UserDefaults = .standard) {
        defaults = userDefaults
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: data)
        {
            settings = stored
        } else {
            settings = AppSettings()
        }
    }

    var playback: PlaybackSettings {
        settings.playback
    }

    var interface: InterfaceSettings {
        settings.interface
    }

    var downloads: DownloadSettings {
        settings.downloads
    }

    func setAutoPlayNextEpisode(_ enabled: Bool) {
        settings.playback.autoPlayNextEpisode = enabled
        persist()
    }

    func setSeekBackwardSeconds(_ seconds: Int) {
        settings.playback.seekBackwardSeconds = seconds
        persist()
    }

    func setSeekForwardSeconds(_ seconds: Int) {
        settings.playback.seekForwardSeconds = seconds
        persist()
    }

    func setPlaybackPlayer(_ player: PlaybackPlayer) {
        settings.playback.player = player
        persist()
    }

    func setSubtitleScale(_ scale: Int) {
        settings.playback.subtitleScale = scale
        persist()
    }

    func setMaxVolumePercent(_ percent: Int) {
        settings.playback.maxVolumePercent = PlaybackSettings.clampVolumePercent(percent)
        persist()
    }

    func updatePlayback(_ transform: (inout PlaybackSettings) -> Void) {
        transform(&settings.playback)
        persist()
    }

    func setHiddenLibraryIds(_ ids: [String]) {
        settings.interface.hiddenLibraryIds = ids.sorted()
        persist()
    }

    func setLibraryDisplayed(_ libraryId: String, displayed: Bool) {
        var hiddenIds = Set(settings.interface.hiddenLibraryIds)
        if displayed {
            hiddenIds.remove(libraryId)
        } else {
            hiddenIds.insert(libraryId)
        }
        settings.interface.hiddenLibraryIds = hiddenIds.sorted()
        persist()
    }

    func setNavigationLibraryIds(_ ids: [String]) {
        settings.interface.navigationLibraryIds = ids
        persist()
    }

    func setDisplayCollections(_ enabled: Bool) {
        settings.interface.displayCollections = enabled
        persist()
    }

    func setDisplayPlaylists(_ enabled: Bool) {
        settings.interface.displayPlaylists = enabled
        persist()
    }

    func setDisplaySeerrDiscoverTab(_ enabled: Bool) {
        settings.interface.displaySeerrDiscoverTab = enabled
        persist()
    }

    func libraryViewSettings(for libraryId: String) -> LibraryViewSettings {
        settings.interface.libraryViewSettingsByLibraryId[libraryId] ?? LibraryViewSettings()
    }

    func setRecommendSectionHidden(_ hidden: Bool, libraryId: String, sectionId: String) {
        var librarySettings = libraryViewSettings(for: libraryId)
        var hiddenIds = Set(librarySettings.hiddenRecommendSectionIds)
        if hidden {
            hiddenIds.insert(sectionId)
        } else {
            hiddenIds.remove(sectionId)
        }
        librarySettings.hiddenRecommendSectionIds = hiddenIds.sorted()
        settings.interface.libraryViewSettingsByLibraryId[libraryId] = librarySettings
        persist()
    }

    func setRecommendSectionOrder(_ sectionIds: [String], libraryId: String) {
        var librarySettings = libraryViewSettings(for: libraryId)
        librarySettings.recommendSectionOrder = sectionIds
        settings.interface.libraryViewSettingsByLibraryId[libraryId] = librarySettings
        persist()
    }

    func resolvedRecommendSectionIds(for libraryId: String, availableSectionIds: [String]) -> [String] {
        guard !availableSectionIds.isEmpty else { return [] }

        let librarySettings = libraryViewSettings(for: libraryId)
        let availableSet = Set(availableSectionIds)

        let orderedKnown = librarySettings.recommendSectionOrder.filter { availableSet.contains($0) }
        let orderedKnownSet = Set(orderedKnown)
        let appended = availableSectionIds.filter { !orderedKnownSet.contains($0) }
        let visibilityOrdered = orderedKnown + appended

        let hiddenIds = Set(librarySettings.hiddenRecommendSectionIds)
        return visibilityOrdered.filter { !hiddenIds.contains($0) }
    }

    func setDownloadWiFiOnly(_ enabled: Bool) {
        settings.downloads.wifiOnly = enabled
        persist()
    }

    func setDownloadQuality(_ quality: DownloadQuality) {
        settings.downloads.quality = quality
        persist()
    }

    private func persist() {
        settings.playback.normalize()
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
