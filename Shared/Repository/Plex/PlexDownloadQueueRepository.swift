import Foundation

enum PlexDownloadQueueItemStatus: String, Codable {
    case deciding
    case waiting
    case processing
    case available
    case error
    case expired
}

struct PlexDownloadQueue: Codable {
    let id: Int
    let status: String
    let itemCount: Int
}

struct PlexAddedDownloadQueueItem: Codable {
    let key: String
    let id: Int
}

struct PlexDownloadDecisionResult: Codable, Hashable {
    let availableBandwidth: Int?
    let generalDecisionCode: Int?
    let generalDecisionText: String?
    let directPlayDecisionCode: Int?
    let directPlayDecisionText: String?
    let transcodeDecisionCode: Int?
    let transcodeDecisionText: String?
}

struct PlexDownloadTranscodeSession: Codable, Hashable {
    let progress: Double?
    let size: Int64?
    let speed: Double?
    let error: Bool?
    let duration: Int64?
    let protocolName: String?
    let sourceVideoCodec: String?
    let sourceAudioCodec: String?

    private enum CodingKeys: String, CodingKey {
        case progress
        case size
        case speed
        case error
        case duration
        case protocolName = "protocol"
        case sourceVideoCodec
        case sourceAudioCodec
    }
}

struct PlexDownloadQueueItem: Codable {
    let id: Int
    let queueId: Int
    let key: String
    let status: PlexDownloadQueueItemStatus
    let error: String?
    let decisionResult: PlexDownloadDecisionResult?
    let transcodeSession: PlexDownloadTranscodeSession?

    private enum CodingKeys: String, CodingKey {
        case id
        case queueId
        case key
        case status
        case error
        case decisionResult = "DecisionResult"
        case transcodeSession = "TranscodeSession"
    }
}

struct PlexDownloadDecisionStream: Codable, Equatable {
    let streamType: Int
    let codec: String?
    let decision: String?
    let bitrate: Int?
    let channels: Int?
    let width: Int?
    let height: Int?
}

struct PlexDownloadDecisionPart: Codable, Equatable {
    let selected: Bool?
    let decision: String?
    let protocolName: String?
    let streams: [PlexDownloadDecisionStream]?

    private enum CodingKeys: String, CodingKey {
        case selected, decision
        case protocolName = "protocol"
        case streams = "Stream"
    }
}

struct PlexDownloadDecisionMedia: Codable, Equatable {
    let selected: Bool?
    let protocolName: String?
    let parts: [PlexDownloadDecisionPart]

    private enum CodingKeys: String, CodingKey {
        case selected
        case protocolName = "protocol"
        case parts = "Part"
    }
}

struct PlexDownloadDecisionMetadata: Codable {
    let media: [PlexDownloadDecisionMedia]

    private enum CodingKeys: String, CodingKey {
        case media = "Media"
    }
}

struct PlexDownloadDecision: Equatable {
    let directPlayDecisionCode: Int?
    let transcodeDecisionCode: Int?
    let media: [PlexDownloadDecisionMedia]

    var selectedPart: PlexDownloadDecisionPart? {
        let selectedMedia = media.first(where: { $0.selected != false }) ?? media.first
        return selectedMedia?.parts.first(where: { $0.selected != false }) ?? selectedMedia?.parts.first
    }
}

struct PlexDownloadDecisionContainer: Codable {
    let directPlayDecisionCode: Int?
    let transcodeDecisionCode: Int?
    let metadata: [PlexDownloadDecisionMetadata]?

    private enum CodingKeys: String, CodingKey {
        case directPlayDecisionCode, transcodeDecisionCode
        case metadata = "Metadata"
    }

    var decision: PlexDownloadDecision {
        PlexDownloadDecision(
            directPlayDecisionCode: directPlayDecisionCode,
            transcodeDecisionCode: transcodeDecisionCode,
            media: metadata?.flatMap(\.media) ?? [],
        )
    }
}

struct PlexDownloadDecisionResponse: Codable {
    let mediaContainer: PlexDownloadDecisionContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

enum PlexDownloadProfileValidationFailure: Error, Equatable {
    case directPlaySelected
    case transcodeNotSelected
    case missingSelectedPart
    case unexpectedProtocol
    case missingVideoStream
    case unexpectedVideoDecision
    case unexpectedVideoCodec
    case videoBitrateExceeded
    case videoResolutionExceeded
    case missingAudioStream
    case unexpectedAudioDecision
    case unexpectedAudioCodec
    case audioBitrateExceeded
    case audioChannelCountExceeded
}

enum PlexDownloadDecisionValidator {
    static func validate(
        _ decision: PlexDownloadDecision,
        profile: DownloadTranscodeProfile,
    ) throws {
        guard decision.directPlayDecisionCode != 1000 else {
            throw PlexDownloadProfileValidationFailure.directPlaySelected
        }
        guard decision.transcodeDecisionCode == 1001 else {
            throw PlexDownloadProfileValidationFailure.transcodeNotSelected
        }
        guard let part = decision.selectedPart else {
            throw PlexDownloadProfileValidationFailure.missingSelectedPart
        }
        guard part.protocolName?.lowercased() == "http" else {
            throw PlexDownloadProfileValidationFailure.unexpectedProtocol
        }

        guard let video = part.streams?.first(where: { $0.streamType == 1 }) else {
            throw PlexDownloadProfileValidationFailure.missingVideoStream
        }
        guard video.decision?.lowercased() == "transcode" else {
            throw PlexDownloadProfileValidationFailure.unexpectedVideoDecision
        }
        guard video.codec?.lowercased() == "h264" else {
            throw PlexDownloadProfileValidationFailure.unexpectedVideoCodec
        }
        guard let videoBitrate = video.bitrate, videoBitrate <= profile.videoBitrateKbps else {
            throw PlexDownloadProfileValidationFailure.videoBitrateExceeded
        }
        guard let width = video.width,
              let height = video.height,
              width <= profile.width,
              height <= profile.height
        else {
            throw PlexDownloadProfileValidationFailure.videoResolutionExceeded
        }

        guard let audio = part.streams?.first(where: { $0.streamType == 2 }) else {
            throw PlexDownloadProfileValidationFailure.missingAudioStream
        }
        guard audio.decision?.lowercased() == "transcode" else {
            throw PlexDownloadProfileValidationFailure.unexpectedAudioDecision
        }
        guard audio.codec?.lowercased() == "aac" else {
            throw PlexDownloadProfileValidationFailure.unexpectedAudioCodec
        }
        guard let audioBitrate = audio.bitrate,
              audioBitrate <= DownloadTranscodeProfile.audioBitrateKbps
        else {
            throw PlexDownloadProfileValidationFailure.audioBitrateExceeded
        }
        guard let channels = audio.channels,
              channels <= DownloadTranscodeProfile.audioChannelCount
        else {
            throw PlexDownloadProfileValidationFailure.audioChannelCountExceeded
        }
    }
}

private struct PlexDownloadQueueContainer: Codable {
    let size: Int
    let downloadQueue: [PlexDownloadQueue]?
    let addedQueueItems: [PlexAddedDownloadQueueItem]?
    let downloadQueueItems: [PlexDownloadQueueItem]?

    private enum CodingKeys: String, CodingKey {
        case size
        case downloadQueue = "DownloadQueue"
        case addedQueueItems = "AddedQueueItems"
        case downloadQueueItems = "DownloadQueueItem"
    }
}

private struct PlexDownloadQueueResponse: Codable {
    let mediaContainer: PlexDownloadQueueContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

enum PlexDownloadQueueRepositoryError: Error {
    case invalidResponse
    case missingQueue
    case missingItem
    case invalidURL
}

final class PlexDownloadQueueRepository {
    static let clientProfileExtra = [
        "add-transcode-target(type=videoProfile&context=streaming&protocol=http&container=mkv&videoCodec=h264&audioCodec=aac&replace=true)",
        "add-limitation(scope=videoAudioCodec&scopeName=aac&type=upperBound&name=audio.bitrate&value=\(DownloadTranscodeProfile.audioBitrateKbps)&replace=true)",
        "add-limitation(scope=videoAudioCodec&scopeName=aac&type=upperBound&name=audio.channels&value=\(DownloadTranscodeProfile.audioChannelCount)&replace=true)",
    ].joined(separator: "+")

    static func plexSessionIdentifier(for downloadID: String) -> String {
        "strimr-download-\(downloadID)"
    }

    private let network: PlexServerNetworkClient
    private let baseURL: URL
    private let authToken: String
    private let clientIdentifier: String
    private let sessionIdentifier: String

    init(context: PlexAPIContext, sessionIdentifier: String? = nil) throws {
        guard let baseURL = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }
        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }
        guard !context.clientIdentifier.isEmpty else {
            throw PlexAPIError.missingConnection
        }

        self.baseURL = baseURL
        self.authToken = authToken
        clientIdentifier = context.clientIdentifier
        self.sessionIdentifier = sessionIdentifier ?? context.clientIdentifier
        network = PlexServerNetworkClient(
            authToken: authToken,
            baseURL: baseURL,
            clientIdentifier: context.clientIdentifier,
        )
    }

    func getOrCreateQueue() async throws -> PlexDownloadQueue {
        let response: PlexDownloadQueueResponse = try await network.request(
            path: "/downloadQueue",
            method: "POST",
            headers: apiHeaders,
        )
        guard let queue = response.mediaContainer.downloadQueue?.first else {
            throw PlexDownloadQueueRepositoryError.missingQueue
        }
        return queue
    }

    func add(
        ratingKey: String,
        to queueID: Int,
        quality: DownloadQuality,
    ) async throws -> PlexAddedDownloadQueueItem {
        let response: PlexDownloadQueueResponse = try await network.request(
            path: "/downloadQueue/\(queueID)/add",
            queryItems: Self.addQueryItems(ratingKey: ratingKey, quality: quality),
            method: "POST",
            headers: apiHeaders,
        )
        guard let item = response.mediaContainer.addedQueueItems?.first else {
            throw PlexDownloadQueueRepositoryError.missingItem
        }
        return item
    }

    func decision(queueID: Int, itemID: Int) async throws -> PlexDownloadDecision {
        let response: PlexDownloadDecisionResponse = try await network.request(
            path: "/downloadQueue/\(queueID)/item/\(itemID)/decision",
            headers: apiHeaders,
        )
        return response.mediaContainer.decision
    }

    static func addQueryItems(
        ratingKey: String,
        quality: DownloadQuality,
    ) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "keys", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "subtitles", value: "embedded"),
            URLQueryItem(name: "advancedSubtitles", value: "text"),
        ]
        if let profile = quality.transcodeProfile {
            queryItems.append(URLQueryItem(name: "autoAdjustQuality", value: "0"))
            queryItems.append(URLQueryItem(name: "directPlay", value: "0"))
            queryItems.append(URLQueryItem(name: "directStream", value: "0"))
            queryItems.append(URLQueryItem(name: "directStreamAudio", value: "0"))
            queryItems.append(URLQueryItem(
                name: "audioChannelCount",
                value: String(DownloadTranscodeProfile.audioChannelCount),
            ))
            queryItems.append(URLQueryItem(name: "videoBitrate", value: String(profile.videoBitrateKbps)))
            queryItems.append(URLQueryItem(name: "peakBitrate", value: String(profile.videoBitrateKbps)))
            queryItems.append(URLQueryItem(name: "videoResolution", value: profile.resolution))
        } else {
            queryItems.append(URLQueryItem(name: "directPlay", value: "1"))
            queryItems.append(URLQueryItem(name: "directStream", value: "1"))
            queryItems.append(URLQueryItem(name: "directStreamAudio", value: "1"))
        }
        return queryItems
    }

    func item(queueID: Int, itemID: Int) async throws -> PlexDownloadQueueItem {
        let response: PlexDownloadQueueResponse = try await network.request(
            path: "/downloadQueue/\(queueID)/items/\(itemID)",
            headers: apiHeaders,
        )
        guard let item = response.mediaContainer.downloadQueueItems?.first else {
            throw PlexDownloadQueueRepositoryError.missingItem
        }
        return item
    }

    func restart(queueID: Int, itemID: Int) async throws {
        try await network.send(
            path: "/downloadQueue/\(queueID)/items/\(itemID)/restart",
            method: "POST",
            headers: apiHeaders,
        )
    }

    func delete(queueID: Int, itemID: Int) async throws {
        try await network.send(
            path: "/downloadQueue/\(queueID)/items/\(itemID)",
            method: "DELETE",
            headers: apiHeaders,
        )
    }

    func mediaRequest(queueID: Int, itemID: Int) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false,
        ) else {
            throw PlexDownloadQueueRepositoryError.invalidURL
        }
        components.path = "/downloadQueue/\(queueID)/item/\(itemID)/media"
        components.query = nil
        guard let url = components.url else {
            throw PlexDownloadQueueRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        for (name, value) in apiHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private var apiHeaders: [String: String] {
        [
            "X-Plex-Pms-Api-Version": "1.0.0",
            "X-Plex-Client-Profile-Name": "generic",
            "X-Plex-Client-Profile-Extra": Self.clientProfileExtra,
            "X-Plex-Session-Identifier": Self.plexSessionIdentifier(for: sessionIdentifier),
        ]
    }
}
