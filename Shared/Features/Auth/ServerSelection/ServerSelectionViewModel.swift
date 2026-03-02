import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false
    var selectingServerID: String?
    var selectedServerID: String?
    var setAsDefault = true
    var isSelecting: Bool {
        selectingServerID != nil
    }
    var canSaveSelection: Bool {
        selectedServerID != nil && !isSelecting
    }

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        self.context = context
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = ResourceRepository(context: context)
            servers = try await repository.getAvailableResources()

            if let currentServer = sessionManager.plexServer,
               servers.contains(where: { $0.clientIdentifier == currentServer.clientIdentifier })
            {
                selectedServerID = currentServer.clientIdentifier
            } else if let defaultServerIdentifier = sessionManager.defaultServerIdentifier,
                      servers.contains(where: { $0.clientIdentifier == defaultServerIdentifier })
            {
                selectedServerID = defaultServerIdentifier
            } else {
                selectedServerID = servers.first?.clientIdentifier
            }

            if let selectedServerID {
                setAsDefault = selectedServerID == sessionManager.defaultServerIdentifier
            } else {
                setAsDefault = true
            }
        } catch {
            ErrorReporter.capture(error)
            servers = []
            selectedServerID = nil
            setAsDefault = true
        }
    }

    func chooseServer(_ server: PlexCloudResource) {
        selectedServerID = server.clientIdentifier
        setAsDefault = true
    }

    func saveSelection() async {
        guard let selectedServerID,
              let server = servers.first(where: { $0.clientIdentifier == selectedServerID })
        else {
            return
        }

        await persistSelection(server: server, setAsDefault: setAsDefault)
    }

    func select(server: PlexCloudResource) async {
        await persistSelection(server: server, setAsDefault: true)
    }

    private func persistSelection(server: PlexCloudResource, setAsDefault: Bool) async {
        guard selectingServerID == nil else { return }
        selectingServerID = server.clientIdentifier
        defer { selectingServerID = nil }

        await sessionManager.selectServer(server, setAsDefault: setAsDefault)
    }
}
