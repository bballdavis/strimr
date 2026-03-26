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
        // Downloads always use the direct media part URL regardless of the quality
        // setting.  The Plex transcoding endpoint (/video/:/transcode/universal/start.mkv)
        // is a streaming-session API that requires a live session cookie carried in
        // request headers; iOS background URLSession download tasks cannot provide
        // those headers after app suspension, causing Plex to return 400 Bad Request.
        // The downloaded file is then saved as the video (89-byte HTML error body),
        // silently completing with corrupt data.
        //
        // Until a proper multi-segment transcoding-download flow is implemented,
        // the direct part URL is the only reliable mechanism for background downloads.
        // The quality parameter is intentionally unused here but retained in the
        // signature so callers require no source changes when transcoding is added.
        _ = quality // reserved for future transcoding-download implementation
        return mediaURL(path: path)
    }
}
