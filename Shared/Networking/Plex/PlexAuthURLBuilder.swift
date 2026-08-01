import Foundation

enum PlexAuthURLBuilder {
    static func url(
        clientIdentifier: String,
        code: String,
        productName: String
    ) -> URL {
        var fragmentQuery = URLComponents()
        fragmentQuery.queryItems = [
            URLQueryItem(name: "clientID", value: clientIdentifier),
            URLQueryItem(name: "context[device][product]", value: productName),
            URLQueryItem(name: "code", value: code)
        ]

        var components = URLComponents()
        components.scheme = "https"
        components.host = "app.plex.tv"
        components.path = "/auth"
        components.percentEncodedFragment = "?\(fragmentQuery.percentEncodedQuery ?? "")"

        precondition(components.url != nil, "Static Plex authentication URL must be valid")
        return components.url!
    }
}
