import Foundation

enum PlexAPIError: Error {
    case invalidURL
    case missingAuthToken
    case missingConnection
    case unreachableServer
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
}

extension Notification.Name {
    static let plexConnectionUnavailable = Notification.Name("plex.connection.unavailable")
}

func isLikelyConnectionAvailabilityError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .secureConnectionFailed,
             .timedOut:
            return true
        default:
            return false
        }
    }

    let nsError = error as NSError
    return nsError.domain == NSURLErrorDomain && isLikelyConnectionAvailabilityError(URLError(_nsError: nsError))
}

func reportPlexConnectionUnavailableIfNeeded(for error: Error) {
    guard isLikelyConnectionAvailabilityError(error) else { return }
    NotificationCenter.default.post(name: .plexConnectionUnavailable, object: nil)
}

protocol QueryItemConvertible {
    var queryItems: [URLQueryItem] { get }
}

extension URLQueryItem {
    static func make(_ name: String, _ value: (some LosslessStringConvertible)?) -> URLQueryItem? {
        value.map { URLQueryItem(name: name, value: String($0)) }
    }

    static func makeArray(_ name: String, _ values: [some LosslessStringConvertible]?) -> URLQueryItem? {
        guard let values, !values.isEmpty else { return nil }
        return URLQueryItem(name: name, value: values.map(String.init).joined(separator: ","))
    }

    static func makeBoolFlag(_ name: String, _ value: Bool?) -> URLQueryItem? {
        value.map { URLQueryItem(name: name, value: $0 ? "1" : "0") }
    }
}

struct PlexPagination {
    let start: Int
    let size: Int

    init(start: Int = 0, size: Int = 20) {
        self.start = max(0, start)
        self.size = max(0, size)
    }

    var headers: [String: String] {
        [
            "X-Plex-Container-Start": String(start),
            "X-Plex-Container-Size": String(size),
        ]
    }
}
