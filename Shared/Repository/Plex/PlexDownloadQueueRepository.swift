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
    private static let clientProfileExtra =
        "append-transcode-target-codec(type=videoProfile&context=streaming&protocol=http&container=mkv&videoCodec=h264&audioCodec=aac)"

    private let network: PlexServerNetworkClient
    private let baseURL: URL
    private let authToken: String
    private let clientIdentifier: String

    init(context: PlexAPIContext) throws {
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

    static func addQueryItems(
        ratingKey: String,
        quality: DownloadQuality,
    ) -> [URLQueryItem] {
        var queryItems = [
            URLQueryItem(name: "keys", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "directPlay", value: "1"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "subtitles", value: "embedded"),
            URLQueryItem(name: "advancedSubtitles", value: "text"),
        ]
        if let profile = quality.transcodeProfile {
            queryItems.append(URLQueryItem(name: "videoBitrate", value: String(profile.videoBitrateKbps)))
            queryItems.append(URLQueryItem(name: "peakBitrate", value: String(profile.videoBitrateKbps)))
            queryItems.append(URLQueryItem(name: "videoResolution", value: profile.resolution))
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
            "X-Plex-Session-Identifier": "strimr-download-\(clientIdentifier)",
        ]
    }
}
