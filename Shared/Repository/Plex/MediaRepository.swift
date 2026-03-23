import Foundation

final class MediaRepository {
    private let baseURL: URL
    private let authToken: String
    private let clientIdentifier: String

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        baseURL = baseURLServer
        self.authToken = authToken
        clientIdentifier = context.clientIdentifier
    }

    func mediaURL(path: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components?.path = normalizedPath
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken),
        ]
        return components?.url
    }

    func downloadURL(path: String, ratingKey: String, quality: DownloadQuality) -> URL? {
        guard let profile = quality.transcodeProfile else {
            return mediaURL(path: path)
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/video/:/transcode/universal/start.mkv"
        components?.queryItems = [
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "session", value: "strimr-download-\(UUID().uuidString.lowercased())"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "1"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "subtitles", value: "none"),
            URLQueryItem(name: "videoQuality", value: "100"),
            URLQueryItem(name: "videoBitrate", value: String(profile.videoBitrateKbps)),
            URLQueryItem(name: "maxVideoBitrate", value: String(profile.maxVideoBitrateKbps)),
            URLQueryItem(name: "videoResolution", value: profile.resolution),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
            URLQueryItem(name: "X-Plex-Platform", value: "iOS"),
            URLQueryItem(name: "X-Plex-Product", value: "Plinx"),
            URLQueryItem(name: "X-Plex-Token", value: authToken),
        ]
        return components?.url
    }
}
