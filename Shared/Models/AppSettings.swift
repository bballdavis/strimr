import Foundation

enum DownloadQuality: String, Codable, CaseIterable, Hashable, Identifiable {
    case original
    case megabits20_1080p
    case megabits12_1080p
    case megabits10_720p
    case megabits4_720p
    case megabits3_720p
    case megabits2_720p
    case kilobits1500_480p
    case kilobits720_328p

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .original:
            "Original"
        case .megabits20_1080p:
            "20 Mbps 1080p"
        case .megabits12_1080p:
            "12 Mbps 1080p"
        case .megabits10_720p:
            "10 Mbps 720p"
        case .megabits4_720p:
            "4 Mbps 720p"
        case .megabits3_720p:
            "3 Mbps 720p"
        case .megabits2_720p:
            "2 Mbps 720p"
        case .kilobits1500_480p:
            "1.5 Mbps 480p"
        case .kilobits720_328p:
            "0.7 Mbps 328p"
        }
    }

    var transcodeProfile: DownloadTranscodeProfile? {
        switch self {
        case .original:
            nil
        case .megabits20_1080p:
            DownloadTranscodeProfile(videoBitrateKbps: 20000, width: 1920, height: 1080)
        case .megabits12_1080p:
            DownloadTranscodeProfile(videoBitrateKbps: 12000, width: 1920, height: 1080)
        case .megabits10_720p:
            DownloadTranscodeProfile(videoBitrateKbps: 10000, width: 1280, height: 720)
        case .megabits4_720p:
            DownloadTranscodeProfile(videoBitrateKbps: 4000, width: 1280, height: 720)
        case .megabits3_720p:
            DownloadTranscodeProfile(videoBitrateKbps: 3000, width: 1280, height: 720)
        case .megabits2_720p:
            DownloadTranscodeProfile(videoBitrateKbps: 2000, width: 1280, height: 720)
        case .kilobits1500_480p:
            DownloadTranscodeProfile(videoBitrateKbps: 1500, width: 848, height: 480)
        case .kilobits720_328p:
            DownloadTranscodeProfile(videoBitrateKbps: 720, width: 640, height: 360)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: (try? container.decode(String.self)) ?? "") ?? .original
    }
}

struct DownloadTranscodeProfile: Equatable {
    let videoBitrateKbps: Int
    let width: Int
    let height: Int

    var resolution: String {
        "\(width)x\(height)"
    }
}

enum SubtitleTextColor: String, Codable, CaseIterable, Hashable {
    case white
    case yellow
    case cyan
}

enum SubtitleFontWeight: String, Codable, CaseIterable, Hashable {
    case regular
    case medium
    case semibold
    case bold
}

enum SubtitleBackgroundStrength: String, Codable, CaseIterable, Hashable {
    case none
    case subtle
    case standard
    case strong
}

enum SubtitleEdgeStyle: String, Codable, CaseIterable, Hashable {
    case shadow
    case outline
    case none
}

enum SubtitleVerticalPosition: String, Codable, CaseIterable, Hashable {
    case bottom
    case middle
    case top
}

struct SubtitleAppearance: Equatable {
    let fontSize: Int
    let textColor: SubtitleTextColor
    let fontWeight: SubtitleFontWeight
    let backgroundStrength: SubtitleBackgroundStrength
    let edgeStyle: SubtitleEdgeStyle
    let verticalPosition: SubtitleVerticalPosition
}

struct PlaybackSettings: Codable, Equatable {
    var autoPlayNextEpisode = true
    var losslessAudio = false
    var seekBackwardSeconds = 10
    var seekForwardSeconds = 10
    var subtitleFontSize = defaultSubtitleFontSize
    var subtitleTextColor = SubtitleTextColor.white
    var subtitleFontWeight = SubtitleFontWeight.semibold
    var subtitleBackgroundStrength = SubtitleBackgroundStrength.standard
    var subtitleEdgeStyle = SubtitleEdgeStyle.shadow
    var subtitleVerticalPosition = SubtitleVerticalPosition.bottom
    var maxVolumePercent = 70

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoPlayNextEpisode = try container.decodeIfPresent(Bool.self, forKey: .autoPlayNextEpisode) ?? true
        losslessAudio = try container.decodeIfPresent(Bool.self, forKey: .losslessAudio) ?? false
        seekBackwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekBackwardSeconds) ?? 10
        seekForwardSeconds = try container.decodeIfPresent(Int.self, forKey: .seekForwardSeconds) ?? 10
        subtitleFontSize = (try? container.decode(Int.self, forKey: .subtitleFontSize))
            ?? Self.defaultSubtitleFontSize
        subtitleTextColor = (try? container.decode(SubtitleTextColor.self, forKey: .subtitleTextColor))
            ?? .white
        subtitleFontWeight = (try? container.decode(SubtitleFontWeight.self, forKey: .subtitleFontWeight))
            ?? .semibold
        subtitleBackgroundStrength = (
            try? container.decode(SubtitleBackgroundStrength.self, forKey: .subtitleBackgroundStrength),
        )
            ?? .standard
        subtitleEdgeStyle = (try? container.decode(SubtitleEdgeStyle.self, forKey: .subtitleEdgeStyle))
            ?? .shadow
        subtitleVerticalPosition = (
            try? container.decode(SubtitleVerticalPosition.self, forKey: .subtitleVerticalPosition),
        )
            ?? .bottom
        maxVolumePercent = try Self.clampVolumePercent(
            container.decodeIfPresent(Int.self, forKey: .maxVolumePercent) ?? 70,
        )
    }

    var subtitleAppearance: SubtitleAppearance {
        SubtitleAppearance(
            fontSize: subtitleFontSize,
            textColor: subtitleTextColor,
            fontWeight: subtitleFontWeight,
            backgroundStrength: subtitleBackgroundStrength,
            edgeStyle: subtitleEdgeStyle,
            verticalPosition: subtitleVerticalPosition,
        )
    }

    mutating func resetSubtitleAppearance() {
        subtitleFontSize = Self.defaultSubtitleFontSize
        subtitleTextColor = .white
        subtitleFontWeight = .semibold
        subtitleBackgroundStrength = .standard
        subtitleEdgeStyle = .shadow
        subtitleVerticalPosition = .bottom
    }

    static func clampVolumePercent(_ percent: Int) -> Int {
        max(0, min(100, percent))
    }

    private static var defaultSubtitleFontSize: Int {
        #if os(tvOS)
            32
        #else
            20
        #endif
    }
}

struct InterfaceSettings: Codable, Equatable {
    var hiddenLibraryIds: [String] = []
    var navigationLibraryIds: [String] = []
    var displayCollections = true
    var displayPlaylists = true
    var displaySeerrDiscoverTab = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraryIds = try container.decodeIfPresent([String].self, forKey: .hiddenLibraryIds) ?? []
        navigationLibraryIds = try container.decodeIfPresent([String].self, forKey: .navigationLibraryIds) ?? []
        displayCollections = try container.decodeIfPresent(Bool.self, forKey: .displayCollections) ?? true
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
