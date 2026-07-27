import Foundation

final class MediaRepository {
    private let baseURL: URL
    private let authToken: String

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        baseURL = baseURLServer
        self.authToken = authToken
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

    func downloadURL(path: String, ratingKey _: String, quality: DownloadQuality) -> URL? {
        // Plex's universal transcode endpoint is a streaming-session API and is
        // not reliable for a background URLSession download. Keep the chosen
        // quality persisted for a future segmented-download implementation,
        // while downloading the original part safely today.
        _ = quality
        return mediaURL(path: path)
    }
}
