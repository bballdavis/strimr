import Foundation

enum DownloadQuality: String, Codable, CaseIterable, Equatable, Identifiable {
    case original
    case megabits20_1080p
    case megabits12_1080p
    case megabits10_720p
    case megabits4_720p
    case megabits3_720p
    case megabits2_720p
    case kilobits1500_480p
    case kilobits720_328p

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "Original"
        case .megabits20_1080p:
            return "20 Mbps 1080p"
        case .megabits12_1080p:
            return "12 Mbps 1080p"
        case .megabits10_720p:
            return "10 Mbps 720p"
        case .megabits4_720p:
            return "4 Mbps 720p"
        case .megabits3_720p:
            return "3 Mbps 720p"
        case .megabits2_720p:
            return "2 Mbps 720p"
        case .kilobits1500_480p:
            return "1.5 Mbps 480p"
        case .kilobits720_328p:
            return "0.7 Mbps 328p"
        }
    }
}

struct LibraryViewSettings: Codable, Equatable {
    var hiddenRecommendSectionIds: [String] = []
    var recommendSectionOrder: [String] = []
}

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var player = PlaybackPlayer.mpv
    var subtitleScale = 100
    var maxVolumePercent = 70

    init() {
        normalize()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        player = try container.decodeIfPresent(PlaybackPlayer.self, forKey: .player) ?? .mpv
        subtitleScale = try container.decodeIfPresent(Int.self, forKey: .subtitleScale) ?? 100
        maxVolumePercent = try container.decodeIfPresent(Int.self, forKey: .maxVolumePercent) ?? 70
        normalize()
    }

    mutating func normalize() {
        maxVolumePercent = Self.clampVolumePercent(maxVolumePercent)
    }

    static func clampVolumePercent(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

struct InterfaceSettings: Codable, Equatable {
    var hiddenLibraryIds: [String] = []
    var navigationLibraryIds: [String] = []
    var libraryViewSettingsByLibraryId: [String: LibraryViewSettings] = [:]
    // Plinx fork: default false — collections are an opt-in feature for kids' context.
    var displayCollections = false
    var displayPlaylists = true
    var displaySeerrDiscoverTab = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraryIds = try container.decodeIfPresent([String].self, forKey: .hiddenLibraryIds) ?? []
        navigationLibraryIds = try container.decodeIfPresent([String].self, forKey: .navigationLibraryIds) ?? []
        libraryViewSettingsByLibraryId = try container.decodeIfPresent([String: LibraryViewSettings].self, forKey: .libraryViewSettingsByLibraryId) ?? [:]
        displayCollections = try container.decodeIfPresent(Bool.self, forKey: .displayCollections) ?? false
        displayPlaylists = try container.decodeIfPresent(Bool.self, forKey: .displayPlaylists) ?? true
        displaySeerrDiscoverTab = try container.decodeIfPresent(Bool.self, forKey: .displaySeerrDiscoverTab) ?? true
    }
}

struct DownloadSettings: Codable, Equatable {
    var wifiOnly = true
    var quality = DownloadQuality.original

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wifiOnly = try container.decodeIfPresent(Bool.self, forKey: .wifiOnly) ?? true
        quality = try container.decodeIfPresent(DownloadQuality.self, forKey: .quality) ?? .original
    }
}

struct AppSettings: Codable, Equatable {
    var playback = PlaybackSettings()
    var interface = InterfaceSettings()
    var downloads = DownloadSettings()

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playback = try container.decodeIfPresent(PlaybackSettings.self, forKey: .playback) ?? PlaybackSettings()
        interface = try container.decodeIfPresent(InterfaceSettings.self, forKey: .interface) ?? InterfaceSettings()
        downloads = try container.decodeIfPresent(DownloadSettings.self, forKey: .downloads) ?? DownloadSettings()
    }
}
