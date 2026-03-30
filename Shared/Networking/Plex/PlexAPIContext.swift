import Foundation

@Observable
final class PlexAPIContext {
    private(set) var authTokenCloud: String?
    private(set) var clientIdentifier: String = ""
    private var resource: PlexCloudResource?
    private(set) var baseURLServer: URL?
    private(set) var authTokenServer: String?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    @ObservationIgnored private let clientIdKey = "strimr.plex.clientId"
    @ObservationIgnored private let connectionKeyPrefix = "strimr.plex.connection"

    init() {
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            let cid = try await ensureClientIdentifier()
            clientIdentifier = cid
        } catch {
            let fallback = UUID().uuidString
            clientIdentifier = fallback
        }
    }

    private func ensureClientIdentifier() async throws -> String {
        if let stored = try keychain.string(forKey: clientIdKey) {
            return stored
        }
        let identifier = UUID().uuidString
        try keychain.setString(identifier, forKey: clientIdKey)
        return identifier
    }

    func waitForBootstrap() async {
        await bootstrapTask?.value
    }

    func setAuthToken(_ token: String) {
        authTokenCloud = token
    }

    var serverIdentifier: String? {
        resource?.clientIdentifier
    }

    func selectServer(_ resource: PlexCloudResource) async throws {
        self.resource = resource
        baseURLServer = nil
        authTokenServer = resource.accessToken

        try await ensureConnection()
    }

    func removeServer() {
        resource = nil
        baseURLServer = nil
        authTokenServer = nil
    }

    @discardableResult
    private func ensureConnection() async throws -> URL {
        guard let resource else {
            throw PlexAPIError.missingConnection
        }
        if let baseURLServer {
            return baseURLServer
        }

        if let savedConnection = loadSavedConnection(for: resource),
           let matchingConnection = resource.connections?.first(where: { $0.uri == savedConnection }),
           try await isConnectionReachable(matchingConnection, accessToken: resource.accessToken)
        {
            baseURLServer = matchingConnection.uri
            return matchingConnection.uri
        }

        guard let connection = try await resolveConnection(using: resource) else {
            throw PlexAPIError.unreachableServer
        }

        baseURLServer = connection.uri
        storeConnection(connection.uri, for: resource)
        return connection.uri
    }

    private func resolveConnection(using resource: PlexCloudResource) async throws -> PlexCloudResource.Connection? {
        guard let connections = resource.connections, !connections.isEmpty else {
            return nil
        }
        let sortedConnections = connections.sorted { lhs, rhs in
            if lhs.isRelay != rhs.isRelay {
                return rhs.isRelay // non-relay first
            }
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal // local first
            }
            return false
        }

        for connection in sortedConnections {
            if try await isConnectionReachable(connection, accessToken: resource.accessToken) {
                return connection
            }
        }

        return nil
    }

    private func isConnectionReachable(
        _ connection: PlexCloudResource.Connection,
        accessToken: String?,
    ) async throws -> Bool {
        var request = URLRequest(url: connection.uri)
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "X-Plex-Token")
        }
        request.timeoutInterval = 6

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode < 500
        } catch {
            return false
        }
    }

    func reset() {
        resource = nil
        authTokenCloud = nil
        baseURLServer = nil
        authTokenServer = nil
    }

    /// Performs a lightweight reachability check against the known Plex
    /// endpoints.  When a server connection URL is available it probes the
    /// local/remote server directly first; if that probe fails it falls back
    /// to probing `plex.tv` (the first network call during hydration).
    /// When no server URL is cached (e.g. after `reset()`) it probes `plex.tv`
    /// directly.
    ///
    /// Returns `true` if any probe target responds within the timeout.
    /// Returns `false` only when all probes fail (network error or timeout).
    ///
    /// This is intentionally a best-effort check used by the offline
    /// pull-to-refresh path to avoid prematurely flipping `isOffline = false`
    /// when the device has WiFi but Plex infrastructure is still unreachable,
    /// which would cause a brief loading-screen flash before re-entering
    /// offline mode.
    func canReachServer() async -> Bool {
        if let serverURL = baseURLServer {
            // Probe the last-known server connection first.
            var request = URLRequest(url: serverURL)
            if let token = authTokenServer {
                request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            }
            request.timeoutInterval = 5
            if let (_, response) = try? await URLSession.shared.data(for: request),
               let http = response as? HTTPURLResponse,
               http.statusCode < 500 {
                return true
            }
            // Server URL probe failed — server may have moved or IP changed.
            // Fall through to plex.tv so hydration can re-resolve the address.
        }

        // Probe plex.tv to verify cloud connectivity.  Hydration requires
        // plex.tv for user/resource lookups and cannot proceed without it.
        guard let plexTV = URL(string: "https://plex.tv") else { return false }
        var fallbackRequest = URLRequest(url: plexTV)
        fallbackRequest.timeoutInterval = 5
        if let (_, response) = try? await URLSession.shared.data(for: fallbackRequest),
           let http = response as? HTTPURLResponse,
           http.statusCode < 500 {
            return true
        }

        return false
    }

    private func connectionKey(for resource: PlexCloudResource) -> String {
        "\(connectionKeyPrefix).\(resource.clientIdentifier)"
    }

    private func loadSavedConnection(for resource: PlexCloudResource) -> URL? {
        do {
            guard let value = try keychain.string(forKey: connectionKey(for: resource)) else {
                return nil
            }
            return URL(string: value)
        } catch {
            return nil
        }
    }

    private func storeConnection(_ url: URL, for resource: PlexCloudResource) {
        do {
            try keychain.setString(url.absoluteString, forKey: connectionKey(for: resource))
        } catch {
            return
        }
    }
}
