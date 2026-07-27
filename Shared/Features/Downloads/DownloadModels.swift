import Foundation

enum DownloadStatus: String, Codable, Hashable {
    case queued
    case downloading
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .downloading:
            true
        case .completed, .failed:
            false
        }
    }
}

enum DownloadArtworkLayoutStyle: String, Codable, Hashable {
    case portrait
    case landscape

    var isPortrait: Bool {
        self == .portrait
    }
}

extension PlexItemType {
    var defaultDownloadArtworkLayoutStyle: DownloadArtworkLayoutStyle {
        switch self {
        case .movie, .show, .season, .episode:
            .portrait
        case .collection, .playlist, .clip, .unknown:
            .landscape
        }
    }
}

struct DownloadedMediaMetadata: Codable, Hashable {
    var ratingKey: String
    var guid: String
    var type: PlexItemType
    var sourceLibrarySectionID: Int? = nil
    /// Preserves the source-library classification for offline artwork when
    /// the live library cache is unavailable.
    var sourceLibraryAgent: String? = nil
    var artworkLayoutStyle: DownloadArtworkLayoutStyle? = nil
    var title: String
    var summary: String?
    var genres: [String]
    var year: Int?
    var duration: TimeInterval?
    var contentRating: String?
    var studio: String?
    var tagline: String?
    var parentRatingKey: String?
    var grandparentRatingKey: String?
    var grandparentTitle: String?
    var parentTitle: String?
    var parentIndex: Int?
    var index: Int?
    var posterFileName: String?
    var videoFileName: String
    var fileSize: Int64?
    var createdAt: Date
    // Optional defaults keep indexes written before offline resume support
    // decodable while allowing local playback state to be persisted separately
    // from Plex's server timeline.
    var viewOffset: TimeInterval? = nil
    var viewCount: Int? = nil
    var lastPlayedAt: Date? = nil

    var resolvedArtworkLayoutStyle: DownloadArtworkLayoutStyle {
        artworkLayoutStyle ?? type.defaultDownloadArtworkLayoutStyle
    }

    var prefersPortraitArtwork: Bool {
        resolvedArtworkLayoutStyle.isPortrait
    }

    var subtitle: String? {
        switch type {
        case .episode:
            if let grandparentTitle, let parentIndex, let index {
                return "\(grandparentTitle) • S\(parentIndex)E\(index)"
            }
            return grandparentTitle ?? parentTitle
        case .movie:
            return year.map(String.init)
        case .season:
            return parentTitle
        case .show:
            return nil
        case .collection, .playlist, .clip, .unknown:
            return nil
        }
    }

    var localMediaItem: MediaItem {
        MediaItem(
            id: ratingKey,
            guid: guid,
            summary: summary,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: genres,
            year: year,
            duration: duration,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: contentRating,
            studio: studio,
            tagline: tagline,
            thumbPath: nil,
            artPath: nil,
            ultraBlurColors: nil,
            viewOffset: viewOffset,
            viewCount: viewCount,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: grandparentTitle,
            parentTitle: parentTitle,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }
}

struct DownloadItem: Codable, Identifiable, Hashable {
    var id: String
    var status: DownloadStatus
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var taskIdentifier: Int?
    var errorMessage: String?
    var metadata: DownloadedMediaMetadata

    var ratingKey: String {
        metadata.ratingKey
    }

    var isPlayable: Bool {
        status == .completed
    }

    var createdAt: Date {
        metadata.createdAt
    }
}

struct DownloadStorageSummary: Equatable {
    var totalBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64
    var downloadsBytes: Int64

    static let empty = DownloadStorageSummary(
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        downloadsBytes: 0,
    )
}
