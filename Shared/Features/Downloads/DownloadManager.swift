import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let backgroundSessionIdentifier = "strimr.downloads.background"
    weak static var shared: DownloadManager?

    private(set) var items: [DownloadItem] = []
    private(set) var isOffline = false
    private(set) var isOnWiFi = false
    private(set) var storageSummary: DownloadStorageSummary = .empty
    private(set) var lastErrorMessage: String?
    private(set) var persistedIndexState: DownloadPersistedIndexState = .missing

    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "strimr.downloads.network-monitor")
    @ObservationIgnored private var backgroundEventsCompletionHandler: (() -> Void)?
    @ObservationIgnored private var progressByTaskIdentifier: [Int: Double] = [:]
    @ObservationIgnored private var isLoadingPersistedState = false
    @ObservationIgnored private var ignoredCompletionIDs: Set<String> = []
    @ObservationIgnored private var preparationTasksByDownloadID: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private weak var activeContext: PlexAPIContext?
    @ObservationIgnored private var contextsByDownloadID: [String: PlexAPIContext] = [:]
    @ObservationIgnored private var cachedLibrariesBySectionID: [Int: Library]?
    @ObservationIgnored private var enrollmentContextProvider: (() -> DownloadEnrollmentContext?)?
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let indexFileURL: URL
    @ObservationIgnored private var backgroundSession: URLSession!

    private static func buildBackgroundSession(delegate: URLSessionDownloadDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.background(
            withIdentifier: Self.backgroundSessionIdentifier,
        )
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        configuration.isDiscretionary = false
        configuration.allowsCellularAccess = true
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    private static func buildDownloadsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return appSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
        downloadsDirectory = Self.buildDownloadsDirectory()
        indexFileURL = downloadsDirectory.appendingPathComponent("index.json")
        super.init()
        backgroundSession = Self.buildBackgroundSession(delegate: self)
        Self.shared = self
        configureStorage()
        loadPersistedState()
        startNetworkMonitoring()
        Task {
            await restoreRunningTasks()
        }
        refreshStorageSummary()
    }

    var sortedItems: [DownloadItem] {
        items.sorted { lhs, rhs in
            if lhs.status.isActive != rhs.status.isActive {
                return lhs.status.isActive
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    var completedItems: [DownloadItem] {
        items.filter { $0.status == .completed }
    }

    var shouldForceOfflineDownloads: Bool {
        isOffline
    }

    func configureEnrollmentContextProvider(
        _ provider: @escaping () -> DownloadEnrollmentContext?,
    ) {
        enrollmentContextProvider = provider
    }

    func status(for ratingKey: String) -> DownloadStatus? {
        scopedItem(for: ratingKey)?.status
    }

    func progress(for ratingKey: String) -> Double? {
        scopedItem(for: ratingKey)?.progress
    }

    func localVideoURL(for item: DownloadItem) -> URL? {
        guard item.status == .completed else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(item.metadata.videoFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localPosterURL(for item: DownloadItem) -> URL? {
        guard let posterFileName = item.metadata.posterFileName else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(posterFileName, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    func localMediaItem(for item: DownloadItem) -> MediaItem {
        item.metadata.localMediaItem
    }

    func updatePlaybackState(
        forDownloadID downloadID: String,
        position: TimeInterval,
        duration: TimeInterval?,
        didFinish: Bool,
    ) {
        guard let index = items.firstIndex(where: { $0.id == downloadID }) else { return }
        guard items[index].status == .completed else { return }

        let clampedPosition = max(0, position)
        items[index].metadata.lastPlayedAt = Date()

        if didFinish {
            items[index].metadata.viewOffset = nil
            items[index].metadata.viewCount = max(items[index].metadata.viewCount ?? 0, 1)
        } else {
            let normalizedDuration = duration ?? items[index].metadata.duration
            let nearBeginning = clampedPosition < 15
            let nearEnd: Bool = if let normalizedDuration, normalizedDuration > 0 {
                clampedPosition >= max(normalizedDuration * 0.95, normalizedDuration - 60)
            } else {
                false
            }

            if nearBeginning || nearEnd {
                items[index].metadata.viewOffset = nil
            } else {
                items[index].metadata.viewOffset = clampedPosition
            }
            items[index].metadata.viewCount = nil
        }

        persistMetadataFile(for: items[index])
        persistState()
    }

    @discardableResult
    func enqueueItem(ratingKey: String, context: PlexAPIContext) async -> [String] {
        let operationContext = context.operationSnapshot()
        let enrollment = enrollmentContextProvider?()
        return await enqueueItem(
            ratingKey: ratingKey,
            context: operationContext,
            enrollment: enrollment,
            requiresEnrollment: enrollmentContextProvider != nil,
        )
    }

    private func enqueueItem(
        ratingKey: String,
        context: PlexAPIContext,
        enrollment: DownloadEnrollmentContext?,
        requiresEnrollment: Bool,
    ) async -> [String] {
        guard !requiresEnrollment || enrollment != nil else {
            lastErrorMessage = String(localized: "downloads.status.failed")
            return []
        }
        guard !isAlreadyScheduled(for: ratingKey, accessScope: enrollment?.scope) else { return [] }

        do {
            activeContext = context
            let metadataRepository = try MetadataRepository(context: context)
            let librariesBySectionID = await loadLibrariesBySectionID(context: context)
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: .init(checkFiles: true),
            )
            guard let plexItem = response.mediaContainer.metadata?.first else { return [] }

            let mediaItem = MediaItem(plexItem: plexItem)
            guard mediaItem.type == .movie || mediaItem.type == .episode else { return [] }
            guard let sourcePart = plexItem.media?.first?.parts.first else { return [] }
            guard let serverIdentifier = context.serverIdentifier else {
                throw PlexAPIError.missingConnection
            }
            if let enrollment, enrollment.scope.serverIdentifier != serverIdentifier {
                throw PlexAPIError.missingConnection
            }

            let id = UUID().uuidString
            let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
            try createDirectoryIfNeeded(at: folderURL)
            try setExcludedFromBackup(at: folderURL)

            let posterFileName = await downloadPosterIfAvailable(
                for: mediaItem,
                context: context,
                destinationFolder: folderURL,
            )

            let requestedQuality = settingsManager.downloads.quality
            let sourceFileSize = sourcePart.size
            let qualityResolution = DownloadSpaceSavingsPolicy.resolve(
                requestedQuality: requestedQuality,
                sourceFileSize: sourceFileSize,
                duration: mediaItem.duration,
            )

            let metadata = DownloadedMediaMetadata(
                ratingKey: mediaItem.id,
                guid: mediaItem.guid,
                type: mediaItem.type,
                sourceLibrarySectionID: plexItem.librarySectionID,
                sourceLibraryAgent: plexItem.librarySectionID.flatMap {
                    librariesBySectionID[$0]
                }?.agent,
                artworkLayoutStyle: preferredArtworkLayoutStyle(
                    for: plexItem,
                    librariesBySectionID: librariesBySectionID,
                ),
                title: mediaItem.title,
                summary: mediaItem.summary,
                genres: mediaItem.genres,
                year: mediaItem.year,
                duration: mediaItem.duration,
                contentRating: mediaItem.contentRating,
                studio: mediaItem.studio,
                tagline: mediaItem.tagline,
                parentRatingKey: mediaItem.parentRatingKey,
                grandparentRatingKey: mediaItem.grandparentRatingKey,
                grandparentTitle: mediaItem.grandparentTitle,
                parentTitle: mediaItem.parentTitle,
                parentIndex: mediaItem.parentIndex,
                index: mediaItem.index,
                posterFileName: posterFileName,
                videoFileName: "video",
                fileSize: nil,
                createdAt: Date(),
            )

            let item = DownloadItem(
                id: id,
                status: .queued,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                taskIdentifier: nil,
                errorMessage: nil,
                requestedQuality: requestedQuality,
                effectiveQuality: qualityResolution.effectiveQuality,
                sourceFileSize: sourceFileSize,
                estimatedOutputBytes: qualityResolution.estimatedOutputBytes,
                qualityResolutionReason: qualityResolution.reason,
                accessScope: enrollment?.scope,
                metadata: metadata,
            )
            do {
                try enrollment?.authorizeAndEnroll(id, metadata)
            } catch {
                try? FileManager.default.removeItem(at: folderURL)
                throw error
            }
            items.append(item)
            contextsByDownloadID[id] = context
            do {
                try persistStateOrThrow()
            } catch {
                items.removeAll { $0.id == id }
                contextsByDownloadID.removeValue(forKey: id)
                try? enrollment?.rollbackEnrollment(id)
                try? FileManager.default.removeItem(at: folderURL)
                throw error
            }

            do {
                if qualityResolution.effectiveQuality == .original {
                    try startOriginalTransfer(
                        downloadID: id,
                        mediaPath: sourcePart.key,
                        context: context,
                    )
                    return [id]
                }

                let queueRepository = try PlexDownloadQueueRepository(
                    context: context,
                    sessionIdentifier: id,
                )
                let queue = try await queueRepository.getOrCreateQueue()
                let remoteItem = try await queueRepository.add(
                    ratingKey: mediaItem.id,
                    to: queue.id,
                    quality: qualityResolution.effectiveQuality,
                )
                guard let index = items.firstIndex(where: { $0.id == id }) else { return [] }
                items[index].status = .deciding
                items[index].remoteReference = RemoteDownloadReference(
                    serverIdentifier: serverIdentifier,
                    queueID: queue.id,
                    itemID: remoteItem.id,
                    cleanupPending: true,
                )
                persistState()
                beginPreparation(forDownloadID: id, context: context)
            } catch {
                markPreparationFailed(downloadID: id, error: error)
            }
            return [id]
        } catch {
            lastErrorMessage = error.localizedDescription
            return []
        }
    }

    @discardableResult
    func enqueueSeason(ratingKey: String, context: PlexAPIContext) async -> [String] {
        let operationContext = context.operationSnapshot()
        let enrollment = enrollmentContextProvider?()
        return await enqueueSeason(
            ratingKey: ratingKey,
            context: operationContext,
            enrollment: enrollment,
            requiresEnrollment: enrollmentContextProvider != nil,
        )
    }

    private func enqueueSeason(
        ratingKey: String,
        context: PlexAPIContext,
        enrollment: DownloadEnrollmentContext?,
        requiresEnrollment: Bool,
    ) async -> [String] {
        guard !requiresEnrollment || enrollment != nil else {
            lastErrorMessage = String(localized: "downloads.status.failed")
            return []
        }
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            let episodes = (response.mediaContainer.metadata ?? []).filter { $0.type == .episode }
            var downloadIDs: [String] = []
            for episode in episodes {
                let episodeIDs = await enqueueItem(
                    ratingKey: episode.ratingKey,
                    context: context,
                    enrollment: enrollment,
                    requiresEnrollment: requiresEnrollment,
                )
                downloadIDs.append(contentsOf: episodeIDs)
            }
            return downloadIDs
        } catch {
            lastErrorMessage = error.localizedDescription
            return []
        }
    }

    @discardableResult
    func enqueueShow(ratingKey: String, context: PlexAPIContext) async -> [String] {
        let operationContext = context.operationSnapshot()
        let enrollment = enrollmentContextProvider?()
        return await enqueueShow(
            ratingKey: ratingKey,
            context: operationContext,
            enrollment: enrollment,
            requiresEnrollment: enrollmentContextProvider != nil,
        )
    }

    private func enqueueShow(
        ratingKey: String,
        context: PlexAPIContext,
        enrollment: DownloadEnrollmentContext?,
        requiresEnrollment: Bool,
    ) async -> [String] {
        guard !requiresEnrollment || enrollment != nil else {
            lastErrorMessage = String(localized: "downloads.status.failed")
            return []
        }
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            let seasons = (response.mediaContainer.metadata ?? []).filter { $0.type == .season }
            var downloadIDs: [String] = []
            for season in seasons {
                let seasonIDs = await enqueueSeason(
                    ratingKey: season.ratingKey,
                    context: context,
                    enrollment: enrollment,
                    requiresEnrollment: requiresEnrollment,
                )
                downloadIDs.append(contentsOf: seasonIDs)
            }
            return downloadIDs
        } catch {
            lastErrorMessage = error.localizedDescription
            return []
        }
    }

    func delete(_ item: DownloadItem) async {
        preparationTasksByDownloadID[item.id]?.cancel()
        preparationTasksByDownloadID[item.id] = nil
        if let taskIdentifier = item.taskIdentifier {
            ignoredCompletionIDs.insert(item.id)
            await cancelTask(with: taskIdentifier)
        }

        if let remote = item.remoteReference,
           let context = contextsByDownloadID[item.id] ?? activeContext,
           context.serverIdentifier == remote.serverIdentifier,
           let repository = try? PlexDownloadQueueRepository(
               context: context,
               sessionIdentifier: item.id,
           )
        {
            try? await repository.delete(queueID: remote.queueID, itemID: remote.itemID)
        }

        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.removeItem(at: folderURL)
        }

        items.removeAll { $0.id == item.id }
        contextsByDownloadID[item.id] = nil
        progressByTaskIdentifier.removeValue(forKey: item.taskIdentifier ?? -1)
        persistState()
        refreshStorageSummary()
    }

    func reconcileArtworkMetadataIfNeeded(context: PlexAPIContext) async {
        var changed = false
        let librariesBySectionID = await loadLibrariesBySectionID(context: context)
        let metadataRepository = try? MetadataRepository(context: context)

        for index in items.indices {
            if items[index].metadata.sourceLibrarySectionID == nil,
               let metadataRepository,
               let response = try? await metadataRepository.getMetadata(
                   ratingKey: items[index].metadata.ratingKey,
               ),
               let plexItem = response.mediaContainer.metadata?.first
            {
                items[index].metadata.sourceLibrarySectionID = plexItem.librarySectionID
            }

            let expectedArtworkLayoutStyle = preferredArtworkLayoutStyle(
                for: items[index].metadata,
                librariesBySectionID: librariesBySectionID,
            )
            if items[index].metadata.artworkLayoutStyle != expectedArtworkLayoutStyle {
                items[index].metadata.artworkLayoutStyle = expectedArtworkLayoutStyle
                persistMetadataFile(for: items[index])
                changed = true
            }
        }

        if changed {
            persistState()
        }
    }

    func setBackgroundEventsCompletionHandler(_ handler: @escaping () -> Void) {
        backgroundEventsCompletionHandler = handler
    }

    func recheckNetworkStatus(serverProbe: (() async -> Bool)? = nil) async {
        let capturedMonitor = monitor
        let pathResult: (isSatisfied: Bool, isWiFi: Bool) = await withCheckedContinuation { continuation in
            monitorQueue.async {
                guard let capturedMonitor else {
                    continuation.resume(returning: (false, false))
                    return
                }
                let path = capturedMonitor.currentPath
                continuation.resume(returning: (
                    path.status == .satisfied,
                    path.usesInterfaceType(.wifi),
                ))
            }
        }

        let serverReachable: Bool = if pathResult.isSatisfied, let serverProbe {
            await serverProbe()
        } else {
            pathResult.isSatisfied
        }

        isOffline = !serverReachable
        isOnWiFi = pathResult.isWiFi && serverReachable
    }

    func resumePendingDownloads(
        context: PlexAPIContext,
        eligibleDownloadIDs: Set<String>? = nil,
    ) {
        activeContext = context
        if let eligibleDownloadIDs {
            let ineligiblePreparationIDs = preparationTasksByDownloadID.keys.filter {
                !eligibleDownloadIDs.contains($0)
            }
            for downloadID in ineligiblePreparationIDs {
                preparationTasksByDownloadID[downloadID]?.cancel()
                preparationTasksByDownloadID[downloadID] = nil
            }
            let ineligibleContextIDs = contextsByDownloadID.keys.filter {
                !eligibleDownloadIDs.contains($0)
            }
            for downloadID in ineligibleContextIDs {
                contextsByDownloadID[downloadID] = nil
            }
        }
        guard let serverIdentifier = context.serverIdentifier else { return }

        for item in items where item.remoteReference?.serverIdentifier == serverIdentifier {
            if let eligibleDownloadIDs, !eligibleDownloadIDs.contains(item.id) {
                continue
            }
            contextsByDownloadID[item.id] = context
            guard let remote = item.remoteReference else { continue }
            if item.status == .completed, remote.cleanupPending {
                Task { [weak self, weak context] in
                    guard let self, let context else { return }
                    await cleanupRemoteItem(downloadID: item.id, context: context)
                }
            } else if item.status == .queued || item.status == .deciding || item.status == .preparing {
                beginPreparation(forDownloadID: item.id, context: context)
            }
        }
    }

    private func beginPreparation(forDownloadID downloadID: String, context: PlexAPIContext) {
        preparationTasksByDownloadID[downloadID]?.cancel()
        preparationTasksByDownloadID[downloadID] = Task { [weak self, weak context] in
            guard let self, let context else { return }
            await pollPreparation(forDownloadID: downloadID, context: context)
        }
    }

    private func pollPreparation(forDownloadID downloadID: String, context: PlexAPIContext) async {
        var consecutiveFailures = 0
        var didRestartExpiredItem = false

        while !Task.isCancelled {
            guard let index = items.firstIndex(where: { $0.id == downloadID }),
                  let remote = items[index].remoteReference,
                  context.serverIdentifier == remote.serverIdentifier
            else {
                preparationTasksByDownloadID[downloadID] = nil
                return
            }

            do {
                let repository = try PlexDownloadQueueRepository(
                    context: context,
                    sessionIdentifier: downloadID,
                )
                let remoteItem = try await repository.item(
                    queueID: remote.queueID,
                    itemID: remote.itemID,
                )
                consecutiveFailures = 0

                guard let refreshedIndex = items.firstIndex(where: { $0.id == downloadID }) else {
                    preparationTasksByDownloadID[downloadID] = nil
                    return
                }

                switch remoteItem.status {
                case .deciding:
                    items[refreshedIndex].status = .deciding
                    items[refreshedIndex].preparationProgress = nil
                case .waiting:
                    items[refreshedIndex].status = .queued
                    items[refreshedIndex].preparationProgress = nil
                case .processing:
                    items[refreshedIndex].status = .preparing
                    items[refreshedIndex].preparationProgress = remoteItem.transcodeSession?.progress
                        .map { min(1, max(0, $0 / 100)) }
                case .available:
                    guard let profile = items[refreshedIndex].effectiveQuality?.transcodeProfile else {
                        await rejectPreparedProfile(
                            downloadID: downloadID,
                            remote: remote,
                            repository: repository,
                        )
                        preparationTasksByDownloadID[downloadID] = nil
                        return
                    }

                    do {
                        let decision = try await repository.decision(
                            queueID: remote.queueID,
                            itemID: remote.itemID,
                        )
                        do {
                            try PlexDownloadDecisionValidator.validate(decision, profile: profile)
                        } catch is PlexDownloadProfileValidationFailure {
                            await rejectPreparedProfile(
                                downloadID: downloadID,
                                remote: remote,
                                repository: repository,
                            )
                            preparationTasksByDownloadID[downloadID] = nil
                            return
                        }

                        guard let validatedIndex = items.firstIndex(where: { $0.id == downloadID }) else {
                            preparationTasksByDownloadID[downloadID] = nil
                            return
                        }
                        items[validatedIndex].deliveryDecision = .transcode
                        persistState()

                        if let preparedSize = remoteItem.transcodeSession?.size,
                           preparedSize > 0,
                           DownloadSpaceSavingsPolicy.shouldReplaceTranscode(
                               downloadedFileSize: preparedSize,
                               sourceFileSize: items[validatedIndex].sourceFileSize,
                               effectiveQuality: items[validatedIndex].effectiveQuality,
                           )
                        {
                            items[validatedIndex].qualityResolutionReason = .actualSavingsTooSmall
                            persistState()
                            try await replaceTranscodeWithOriginal(
                                downloadID: downloadID,
                                context: context,
                            )
                            preparationTasksByDownloadID[downloadID] = nil
                            return
                        }

                        try startPreparedTransfer(
                            downloadID: downloadID,
                            remote: remote,
                            repository: repository,
                        )
                    } catch {
                        markPreparationFailed(downloadID: downloadID, error: error)
                    }
                    preparationTasksByDownloadID[downloadID] = nil
                    return
                case .expired:
                    guard !didRestartExpiredItem else {
                        markPreparationFailed(
                            downloadID: downloadID,
                            error: PlexDownloadQueueRepositoryError.invalidResponse,
                        )
                        preparationTasksByDownloadID[downloadID] = nil
                        return
                    }
                    try await repository.restart(queueID: remote.queueID, itemID: remote.itemID)
                    didRestartExpiredItem = true
                    items[refreshedIndex].status = .queued
                    items[refreshedIndex].preparationProgress = nil
                case .error:
                    items[refreshedIndex].status = .failed
                    items[refreshedIndex].taskIdentifier = nil
                    items[refreshedIndex].errorMessage = String(localized: "downloads.status.failed")
                    persistState()
                    preparationTasksByDownloadID[downloadID] = nil
                    return
                }
                items[refreshedIndex].errorMessage = nil
                persistState()
            } catch {
                if Task.isCancelled {
                    preparationTasksByDownloadID[downloadID] = nil
                    return
                }
                consecutiveFailures += 1
                lastErrorMessage = error.localizedDescription
                if consecutiveFailures >= 5 {
                    markPreparationFailed(downloadID: downloadID, error: error)
                    preparationTasksByDownloadID[downloadID] = nil
                    return
                }
            }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        preparationTasksByDownloadID[downloadID] = nil
    }

    private func startPreparedTransfer(
        downloadID: String,
        remote: RemoteDownloadReference,
        repository: PlexDownloadQueueRepository,
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == downloadID }) else { return }
        guard items[index].taskIdentifier == nil else { return }

        var request = try repository.mediaRequest(queueID: remote.queueID, itemID: remote.itemID)
        if settingsManager.downloads.wifiOnly {
            request.allowsCellularAccess = false
            request.allowsConstrainedNetworkAccess = false
            request.allowsExpensiveNetworkAccess = false
        }

        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = downloadID
        items[index].status = .downloading
        items[index].progress = 0
        items[index].preparationProgress = 1
        items[index].taskIdentifier = task.taskIdentifier
        items[index].errorMessage = nil
        persistState()
        task.resume()
    }

    private func markPreparationFailed(downloadID: String, error: Error) {
        guard let index = items.firstIndex(where: { $0.id == downloadID }) else { return }
        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].errorMessage = String(localized: "downloads.status.failed")
        lastErrorMessage = error.localizedDescription
        persistState()
    }

    private func rejectPreparedProfile(
        downloadID: String,
        remote: RemoteDownloadReference,
        repository: PlexDownloadQueueRepository,
    ) async {
        try? await repository.delete(queueID: remote.queueID, itemID: remote.itemID)
        guard let index = items.firstIndex(where: { $0.id == downloadID }) else { return }
        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].remoteReference?.cleanupPending = false
        items[index].qualityResolutionReason = .serverRejectedProfile
        items[index].errorMessage = String(localized: "downloads.status.failed")
        persistState()
    }

    private func cleanupRemoteItem(downloadID: String, context: PlexAPIContext) async {
        guard let index = items.firstIndex(where: { $0.id == downloadID }),
              let remote = items[index].remoteReference,
              context.serverIdentifier == remote.serverIdentifier,
              let repository = try? PlexDownloadQueueRepository(
                  context: context,
                  sessionIdentifier: downloadID,
              )
        else {
            return
        }

        do {
            try await repository.delete(queueID: remote.queueID, itemID: remote.itemID)
            guard let refreshedIndex = items.firstIndex(where: { $0.id == downloadID }) else { return }
            items[refreshedIndex].remoteReference?.cleanupPending = false
            contextsByDownloadID[downloadID] = nil
            persistState()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func startNetworkMonitoring() {
        guard monitor == nil else { return }

        let newMonitor = NWPathMonitor()
        newMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isOffline = path.status != .satisfied
                self.isOnWiFi = path.usesInterfaceType(.wifi)
            }
        }
        newMonitor.start(queue: monitorQueue)
        monitor = newMonitor
    }

    func stopNetworkMonitoring() {
        monitor?.cancel()
        monitor = nil
    }

    private func configureStorage() {
        do {
            try createDirectoryIfNeeded(at: downloadsDirectory)
            try setExcludedFromBackup(at: downloadsDirectory)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
        )
    }

    private func setExcludedFromBackup(at url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func downloadPosterIfAvailable(
        for mediaItem: MediaItem,
        context: PlexAPIContext,
        destinationFolder: URL,
    ) async -> String? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = mediaItem.preferredThumbPath else { return nil }
        guard let posterURL = imageRepository.transcodeImageURL(path: thumbPath, width: 480, height: 720)
        else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: posterURL)
            guard !data.isEmpty else { return nil }
            let fileName = "poster.jpg"
            let destination = destinationFolder.appendingPathComponent(fileName, isDirectory: false)
            try data.write(to: destination, options: .atomic)
            try setExcludedFromBackup(at: destination)
            return fileName
        } catch {
            return nil
        }
    }

    private func loadLibrariesBySectionID(context: PlexAPIContext) async -> [Int: Library] {
        if let cachedLibrariesBySectionID {
            return cachedLibrariesBySectionID
        }

        guard let sectionRepository = try? SectionRepository(context: context) else {
            return [:]
        }

        do {
            let response = try await sectionRepository.getSections()
            let libraries = (response.mediaContainer.directory ?? [])
                .filter(\.type.isSupported)
                .map(Library.init)
            let librariesBySectionID: [Int: Library] = Dictionary(
                uniqueKeysWithValues: libraries.compactMap { library in
                    guard let sectionID = library.sectionId else { return nil }
                    return (sectionID, library)
                },
            )
            cachedLibrariesBySectionID = librariesBySectionID
            return librariesBySectionID
        } catch {
            return [:]
        }
    }

    private func preferredArtworkLayoutStyle(
        for plexItem: PlexItem,
        librariesBySectionID: [Int: Library],
    ) -> DownloadArtworkLayoutStyle {
        if plexItem.type == .movie,
           let sectionID = plexItem.librarySectionID,
           let library = librariesBySectionID[sectionID],
           library.isNoneAgentLibrary
        {
            return .landscape
        }

        return plexItem.type.defaultDownloadArtworkLayoutStyle
    }

    private func preferredArtworkLayoutStyle(
        for metadata: DownloadedMediaMetadata,
        librariesBySectionID: [Int: Library],
    ) -> DownloadArtworkLayoutStyle {
        if metadata.type == .movie,
           let sectionID = metadata.sourceLibrarySectionID,
           let library = librariesBySectionID[sectionID],
           library.isNoneAgentLibrary
        {
            return .landscape
        }

        return metadata.type.defaultDownloadArtworkLayoutStyle
    }

    private func scopedItem(for ratingKey: String) -> DownloadItem? {
        guard enrollmentContextProvider != nil else {
            return newestPreferredItem(in: items.filter { $0.ratingKey == ratingKey })
        }
        guard let scope = enrollmentContextProvider?()?.scope else { return nil }
        return newestPreferredItem(in: items.filter { item in
            item.ratingKey == ratingKey && item.accessScope == scope
        })
    }

    private func newestPreferredItem(in candidates: [DownloadItem]) -> DownloadItem? {
        candidates.last(where: { $0.status.isActive }) ?? candidates.last
    }

    private func isAlreadyScheduled(
        for ratingKey: String,
        accessScope: DownloadAccessScope?,
    ) -> Bool {
        items.contains { item in
            item.ratingKey == ratingKey
                && item.accessScope == accessScope
                && item.status != .failed
        }
    }

    private func persistState() {
        do {
            try persistStateOrThrow()
        } catch let failure as DownloadPersistenceFailure {
            ErrorReporter.capture(failure)
        } catch {
            ErrorReporter.capture(DownloadPersistenceFailure.indexWrite)
        }
    }

    private func persistStateOrThrow() throws {
        guard !isLoadingPersistedState else { return }
        guard persistedIndexState.permitsPersistence else {
            throw DownloadPersistenceFailure.indexWrite
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(items)
        } catch {
            throw DownloadPersistenceFailure.indexEncode
        }

        do {
            try data.write(to: indexFileURL, options: .atomic)
            persistedIndexState = .loaded
        } catch {
            throw DownloadPersistenceFailure.indexWrite
        }
    }

    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else {
            persistedIndexState = .missing
            return
        }
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }

        let data: Data
        do {
            data = try Data(contentsOf: indexFileURL)
        } catch {
            persistedIndexState = .unreadable
            ErrorReporter.capture(DownloadPersistenceFailure.indexRead)
            return
        }

        do {
            items = try JSONDecoder().decode([DownloadItem].self, from: data)
            persistedIndexState = .loaded
        } catch {
            // Keep both the last known in-memory state and index file available for recovery.
            persistedIndexState = .corrupt
            ErrorReporter.capture(DownloadPersistenceFailure.indexDecode)
        }
    }

    private func refreshStorageSummary() {
        let downloadsBytes = items.reduce(into: Int64(0)) { partialResult, item in
            if item.status == .completed {
                partialResult += item.metadata.fileSize ?? 0
            }
        }

        let fileSystemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let totalBytes = (fileSystemAttributes?[.systemSize] as? NSNumber)?.int64Value ?? 0
        let freeBytes = (fileSystemAttributes?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let usedBytes = max(0, totalBytes - freeBytes)

        storageSummary = DownloadStorageSummary(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: freeBytes,
            downloadsBytes: downloadsBytes,
        )
    }

    private func persistMetadataFile(for item: DownloadItem) {
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let metadataURL = folderURL.appendingPathComponent("metadata.json", isDirectory: false)

        let data: Data
        do {
            data = try JSONEncoder().encode(item.metadata)
        } catch {
            ErrorReporter.capture(DownloadPersistenceFailure.metadataEncode)
            return
        }

        do {
            try data.write(to: metadataURL, options: .atomic)
            try setExcludedFromBackup(at: metadataURL)
        } catch {
            ErrorReporter.capture(DownloadPersistenceFailure.metadataWrite)
        }
    }

    private func updateItem(_ transform: (inout DownloadItem) -> Void, matchingTask task: URLSessionTask) {
        guard let index = itemIndex(for: task) else { return }
        transform(&items[index])
    }

    private func itemIndex(for task: URLSessionTask) -> Int? {
        if let description = task.taskDescription,
           let descriptionIndex = items.firstIndex(where: { $0.id == description })
        {
            return descriptionIndex
        }

        return items.firstIndex(where: { $0.taskIdentifier == task.taskIdentifier })
    }

    private func restoreRunningTasks() async {
        guard persistedIndexState == .loaded else { return }
        let tasks = await allTasks()
        let runningTaskIDs = Set(tasks.map(\.taskIdentifier))

        for index in items.indices {
            if let taskIdentifier = items[index].taskIdentifier, runningTaskIDs.contains(taskIdentifier) {
                items[index].status = .downloading
                items[index].errorMessage = nil
            } else if items[index].remoteReference != nil,
                      [.queued, .deciding, .preparing].contains(items[index].status)
            {
                items[index].taskIdentifier = nil
            } else if items[index].status.isActive {
                items[index].status = .failed
                items[index].errorMessage = String(localized: "downloads.status.interrupted")
                items[index].taskIdentifier = nil
            }
        }

        persistState()
    }

    private func allTasks() async -> [URLSessionTask] {
        await withCheckedContinuation { continuation in
            backgroundSession.getAllTasks { tasks in
                continuation.resume(returning: tasks)
            }
        }
    }

    private func cancelTask(with identifier: Int) async {
        let tasks = await allTasks()
        tasks.first { $0.taskIdentifier == identifier }?.cancel()
    }

    private func sanitizeFileName(_ value: String) -> String {
        value.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "_",
            options: .regularExpression,
        )
    }

    private func resolveDownloadDestination(
        for item: DownloadItem,
        response: URLResponse?,
    ) -> URL {
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let suggestedName = (response?.suggestedFilename).flatMap { sanitizeFileName($0) }
        let fallback = sanitizeFileName(item.metadata.title) + ".mp4"
        let fileName = suggestedName?.isEmpty == false ? suggestedName! : fallback
        return folderURL.appendingPathComponent(fileName, isDirectory: false)
    }

    private func completeDownload(task: URLSessionDownloadTask, stagedLocation: URL) async {
        guard let index = itemIndex(for: task) else {
            removeStagedFileIfPresent(at: stagedLocation)
            return
        }
        let item = items[index]
        let destination = resolveDownloadDestination(for: item, response: task.response)
        var movedStagedFile = false

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: stagedLocation.path)
            let stagedFileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            try DownloadIntegrityValidator.validate(
                response: task.response,
                stagedFileSize: stagedFileSize,
            )

            if DownloadSpaceSavingsPolicy.shouldReplaceTranscode(
                downloadedFileSize: stagedFileSize,
                sourceFileSize: item.sourceFileSize,
                effectiveQuality: item.effectiveQuality,
            ), let context = contextsByDownloadID[item.id] {
                removeStagedFileIfPresent(at: stagedLocation)
                items[index].qualityResolutionReason = .actualSavingsTooSmall
                persistState()
                try await replaceTranscodeWithOriginal(downloadID: item.id, context: context)
                return
            }

            try createDirectoryIfNeeded(at: destination.deletingLastPathComponent())

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(at: stagedLocation, to: destination)
            movedStagedFile = true
            try setExcludedFromBackup(at: destination)

            items[index].status = .completed
            items[index].progress = 1
            items[index].bytesWritten = stagedFileSize
            items[index].totalBytes = stagedFileSize
            items[index].taskIdentifier = nil
            items[index].errorMessage = nil
            items[index].metadata.videoFileName = destination.lastPathComponent
            items[index].metadata.fileSize = stagedFileSize

            persistMetadataFile(for: items[index])
            persistState()
            refreshStorageSummary()
            if let downloadContext = contextsByDownloadID[items[index].id] {
                if items[index].remoteReference == nil {
                    contextsByDownloadID[items[index].id] = nil
                } else {
                    await cleanupRemoteItem(downloadID: items[index].id, context: downloadContext)
                }
            }
        } catch {
            removeStagedFileIfPresent(at: stagedLocation)
            if movedStagedFile {
                try? FileManager.default.removeItem(at: destination)
            }
            if let statusCode = (task.response as? HTTPURLResponse)?.statusCode,
               statusCode == 404 || statusCode == 503,
               let activeContext,
               items[index].remoteReference?.serverIdentifier == activeContext.serverIdentifier
            {
                items[index].status = .preparing
                items[index].taskIdentifier = nil
                items[index].errorMessage = nil
                persistState()
                beginPreparation(forDownloadID: items[index].id, context: activeContext)
                return
            }
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = String(localized: "downloads.status.failed")
            persistState()
        }
    }

    private func removeStagedFileIfPresent(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func startOriginalTransfer(
        downloadID: String,
        mediaPath: String,
        context: PlexAPIContext,
    ) throws {
        guard let index = items.firstIndex(where: { $0.id == downloadID }) else { return }
        let mediaRepository = try MediaRepository(context: context)
        guard let mediaURL = mediaRepository.mediaURL(path: mediaPath) else {
            throw PlexDownloadQueueRepositoryError.invalidURL
        }

        var request = URLRequest(url: mediaURL)
        if settingsManager.downloads.wifiOnly {
            request.allowsCellularAccess = false
            request.allowsConstrainedNetworkAccess = false
            request.allowsExpensiveNetworkAccess = false
        }

        let task = backgroundSession.downloadTask(with: request)
        task.taskDescription = downloadID
        items[index].effectiveQuality = .original
        items[index].deliveryDecision = .directPlay
        items[index].remoteReference = nil
        items[index].status = .downloading
        items[index].progress = 0
        items[index].preparationProgress = nil
        items[index].bytesWritten = 0
        items[index].totalBytes = 0
        items[index].taskIdentifier = task.taskIdentifier
        items[index].errorMessage = nil
        persistState()
        task.resume()
    }

    private func replaceTranscodeWithOriginal(
        downloadID: String,
        context: PlexAPIContext,
    ) async throws {
        guard let index = items.firstIndex(where: { $0.id == downloadID }),
              let remote = items[index].remoteReference,
              context.serverIdentifier == remote.serverIdentifier
        else {
            throw PlexDownloadQueueRepositoryError.invalidResponse
        }

        let metadataRepository = try MetadataRepository(context: context)
        let response = try await metadataRepository.getMetadata(
            ratingKey: items[index].ratingKey,
            params: .init(checkFiles: true),
        )
        guard let sourcePart = response.mediaContainer.metadata?.first?.media?.first?.parts.first else {
            throw PlexDownloadQueueRepositoryError.invalidResponse
        }

        let repository = try PlexDownloadQueueRepository(
            context: context,
            sessionIdentifier: downloadID,
        )
        try? await repository.delete(queueID: remote.queueID, itemID: remote.itemID)

        guard let refreshedIndex = items.firstIndex(where: { $0.id == downloadID }) else {
            throw PlexDownloadQueueRepositoryError.invalidResponse
        }
        items[refreshedIndex].sourceFileSize = sourcePart.size ?? items[refreshedIndex].sourceFileSize
        try startOriginalTransfer(
            downloadID: downloadID,
            mediaPath: sourcePart.key,
            context: context,
        )
    }

    private nonisolated static func stageDownloadFile(at location: URL) throws -> URL {
        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("strimr-download-staging", isDirectory: true)
        try FileManager.default.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true,
        )

        let stagedURL = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: false)
        if FileManager.default.fileExists(atPath: stagedURL.path) {
            try FileManager.default.removeItem(at: stagedURL)
        }
        try FileManager.default.moveItem(at: location, to: stagedURL)
        return stagedURL
    }

    private func failDownload(task: URLSessionTask, error: Error) {
        guard let index = itemIndex(for: task) else { return }
        let itemID = items[index].id
        guard !ignoredCompletionIDs.contains(itemID) else {
            ignoredCompletionIDs.remove(itemID)
            return
        }

        items[index].status = .failed
        items[index].taskIdentifier = nil
        items[index].errorMessage = error.localizedDescription
        persistState()
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64,
    ) {
        Task { @MainActor in
            guard totalBytesExpectedToWrite > 0 else { return }
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            let previousProgress = progressByTaskIdentifier[downloadTask.taskIdentifier] ?? -1
            guard progress - previousProgress >= 0.01 || progress == 1 else { return }
            progressByTaskIdentifier[downloadTask.taskIdentifier] = progress

            updateItem({ item in
                item.status = .downloading
                item.progress = progress
                item.bytesWritten = totalBytesWritten
                item.totalBytes = totalBytesExpectedToWrite
            }, matchingTask: downloadTask)
            persistState()
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL,
    ) {
        do {
            let stagedURL = try Self.stageDownloadFile(at: location)
            Task { @MainActor in
                await completeDownload(task: downloadTask, stagedLocation: stagedURL)
            }
        } catch {
            Task { @MainActor in
                failDownload(task: downloadTask, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?,
    ) {
        guard let error else { return }
        Task { @MainActor in
            failDownload(task: task, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession _: URLSession) {
        Task { @MainActor in
            backgroundEventsCompletionHandler?()
            backgroundEventsCompletionHandler = nil
        }
    }
}

private enum DownloadPersistenceFailure: Error {
    case indexEncode
    case indexWrite
    case indexRead
    case indexDecode
    case metadataEncode
    case metadataWrite
}
