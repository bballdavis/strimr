import Foundation
import Observation

@MainActor
@Observable
final class SessionManager {
    enum Status {
        case hydrating
        case signedOut
        case needsProfileSelection
        case needsServerSelection
        case ready
    }

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let libraryStore: LibraryStore
    private(set) var status: Status = .hydrating
    private(set) var authToken: String?
    private(set) var user: PlexCloudUser?
    private(set) var plexServer: PlexCloudResource?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    @ObservationIgnored private let tokenKey = "strimr.plex.authToken"
    @ObservationIgnored private let legacyServerIdDefaultsKey = "strimr.plex.serverIdentifier"
    /// Key used by older Plinx builds (pre-rename). Checked only during migration.
    @ObservationIgnored private let legacyPlinxServerIdDefaultsKey = "plinx.plex.defaultServerIdentifier"
    @ObservationIgnored private let defaultServerIdDefaultsKey = "strimr.plex.defaultServerIdentifier"
    private(set) var defaultServerIdentifier: String?

    init(context: PlexAPIContext, libraryStore: LibraryStore) {
        self.context = context
        self.libraryStore = libraryStore
        let defaults = UserDefaults.standard
        if let defaultServerId = defaults.string(forKey: defaultServerIdDefaultsKey) {
            defaultServerIdentifier = defaultServerId
        } else if let plinxServerId = defaults.string(forKey: legacyPlinxServerIdDefaultsKey) {
            // Migrate from the old Plinx-branded key used before this rename.
            defaults.set(plinxServerId, forKey: defaultServerIdDefaultsKey)
            defaults.removeObject(forKey: legacyPlinxServerIdDefaultsKey)
            defaultServerIdentifier = plinxServerId
        } else if let legacyServerId = defaults.string(forKey: legacyServerIdDefaultsKey) {
            defaults.set(legacyServerId, forKey: defaultServerIdDefaultsKey)
            defaultServerIdentifier = legacyServerId
        }
        Task { await hydrate() }
    }

    func hydrate() async {
        status = .hydrating
        do {
            await context.waitForBootstrap()

            let storedToken = try keychain.string(forKey: tokenKey)
            authToken = storedToken
            if let storedToken {
                context.setAuthToken(storedToken)
            }

            if let token = storedToken {
                try await bootstrapAuthenticatedSession(
                    with: token,
                    allowProfileSelection: false,
                )
            } else {
                status = .signedOut
            }
        } catch {
            await clearSession()
            status = .signedOut
        }
    }

    func signIn(with token: String) async throws {
        do {
            try keychain.setString(token, forKey: tokenKey)
            authToken = token
            context.setAuthToken(token)
            try await bootstrapAuthenticatedSession(
                with: token,
                allowProfileSelection: true,
            )
        } catch {
            await clearSession()
            status = .signedOut
            throw error
        }
    }

    func signOut() async {
        await clearSession()
        try? keychain.deleteValue(forKey: tokenKey)
        UserDefaults.standard.removeObject(forKey: legacyServerIdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: legacyPlinxServerIdDefaultsKey)
        UserDefaults.standard.removeObject(forKey: defaultServerIdDefaultsKey)
        defaultServerIdentifier = nil
        status = .signedOut
    }

    func switchProfile(to user: PlexCloudUser) async throws {
        let snapshot = (token: authToken, user: self.user, server: plexServer, status: status)

        do {
            try keychain.setString(user.authToken, forKey: tokenKey)
            authToken = user.authToken
            self.user = user
            context.setAuthToken(user.authToken)
            try await bootstrapAuthenticatedSession(
                with: user.authToken,
                allowProfileSelection: false,
            )
        } catch {
            if let token = snapshot.token {
                try? keychain.setString(token, forKey: tokenKey)
                authToken = token
                context.setAuthToken(token)
            }
            self.user = snapshot.user
            plexServer = snapshot.server
            status = snapshot.status
            throw error
        }
    }

    func selectServer(_ server: PlexCloudResource, setAsDefault: Bool? = nil) async {
        do {
            try await context.selectServer(server)
            plexServer = server
            if let setAsDefault {
                updateDefaultServer(serverId: setAsDefault ? server.clientIdentifier : nil)
            }
            if authToken != nil {
                try? await libraryStore.reloadLibraries()
                status = .ready
            }
        } catch {
            plexServer = nil
            context.removeServer()
            status = .needsServerSelection
        }
    }

    func updateDefaultServer(serverId: String?) {
        defaultServerIdentifier = serverId
        if let serverId {
            UserDefaults.standard.set(serverId, forKey: defaultServerIdDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultServerIdDefaultsKey)
        }
    }

    func requestProfileSelection() async {
        status = .needsProfileSelection
        plexServer = nil
        context.removeServer()
    }

    func requestServerSelection() async {
        status = .needsServerSelection
        plexServer = nil
        context.removeServer()
    }

    func bootstrapDirectServerSession(
        resource: PlexCloudResource,
        token: String,
        setAsDefault: Bool = true
    ) async {
        authToken = token
        context.setAuthToken(token)
        await selectServer(resource, setAsDefault: setAsDefault)
    }

    private func bootstrapAuthenticatedSession(
        with token: String,
        allowProfileSelection: Bool,
    ) async throws {
        let userRepo = UserRepository(context: context)
        let resourcesRepo = ResourceRepository(context: context)

        let userResponse = try await userRepo.getUser()
        user = userResponse
        authToken = token

        if allowProfileSelection {
            do {
                let home = try await userRepo.getHomeUsers()
                if home.users.count > 1 {
                    status = .needsProfileSelection
                    context.removeServer()
                    plexServer = nil
                    return
                }
            } catch {}
        }

        let resources = try await resourcesRepo.getAvailableResources()

          if let defaultServerIdentifier,
              let server = resources.first(where: { $0.clientIdentifier == defaultServerIdentifier })
        {
            await selectServer(server)
        } else if resources.count == 1, let server = resources.first {
            await selectServer(server)
        } else {
            plexServer = nil
            context.removeServer()
            status = .needsServerSelection
        }
    }

    private func clearSession() async {
        authToken = nil
        user = nil
        plexServer = nil
        context.reset()
    }
}
