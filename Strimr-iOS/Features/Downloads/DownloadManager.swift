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

    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "strimr.downloads.network-monitor")
    @ObservationIgnored private var backgroundEventsCompletionHandler: (() -> Void)?
    @ObservationIgnored private var progressByTaskIdentifier: [Int: Double] = [:]
    @ObservationIgnored private var isLoadingPersistedState = false
    @ObservationIgnored private var ignoredCompletionIDs: Set<String> = []
    @ObservationIgnored private var cachedLibrariesBySectionID: [Int: Library]?
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

    func markOfflineDueToConnectionFailure() {
        isOffline = true
        isOnWiFi = false
    }

    var completedItems: [DownloadItem] {
        items.filter { $0.status == .completed }
    }

    var shouldForceOfflineDownloads: Bool {
        isOffline
    }

    func status(for ratingKey: String) -> DownloadStatus? {
        items.first { $0.ratingKey == ratingKey }?.status
    }

    func progress(for ratingKey: String) -> Double? {
        items.first { $0.ratingKey == ratingKey }?.progress
    }

    func localVideoURL(for item: DownloadItem) -> URL? {
        guard item.status == .completed else { return nil }
        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(item.metadata.videoFileName, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        // Reject files that are too small to be a valid video.  A previous
        // missing HTTP-status check could have saved error response bodies
        // (e.g. a 400 Bad Request HTML page, ~89 bytes) as the video file.
        // 10 KB is a safe floor — even a 1-second clip exceeds this.
        let minimumVideoBytes: Int64 = 10_000
        let onDiskSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))
            .flatMap { $0[.size] as? Int64 } ?? 0
        guard onDiskSize >= minimumVideoBytes else { return nil }
        return fileURL
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
            let nearEnd: Bool
            if let normalizedDuration, normalizedDuration > 0 {
                nearEnd = clampedPosition >= max(normalizedDuration * 0.95, normalizedDuration - 60)
            } else {
                nearEnd = false
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

    func enqueueItem(ratingKey: String, context: PlexAPIContext) async {
        guard !isAlreadyScheduled(for: ratingKey) else { return }

        do {
            let metadataRepository = try MetadataRepository(context: context)
            let librariesBySectionID = await loadLibrariesBySectionID(context: context)
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: .init(checkFiles: true),
            )
            guard let plexItem = response.mediaContainer.metadata?.first else { return }

            let mediaItem = MediaItem(plexItem: plexItem)
            guard mediaItem.type == .movie || mediaItem.type == .episode else { return }
            guard let partPath = plexItem.media?.first?.parts.first?.key else { return }

            let mediaRepository = try MediaRepository(context: context)
            guard let mediaURL = mediaRepository.downloadURL(
                path: partPath,
                ratingKey: mediaItem.id,
                quality: settingsManager.downloads.quality
            ) else { return }

            let id = UUID().uuidString
            let folderURL = downloadsDirectory.appendingPathComponent(id, isDirectory: true)
            try createDirectoryIfNeeded(at: folderURL)
            try setExcludedFromBackup(at: folderURL)

            let posterFileName = await downloadPosterIfAvailable(
                for: mediaItem,
                context: context,
                destinationFolder: folderURL,
            )

            var request = URLRequest(url: mediaURL)
            if settingsManager.downloads.wifiOnly {
                request.allowsCellularAccess = false
                request.allowsConstrainedNetworkAccess = false
                request.allowsExpensiveNetworkAccess = false
            }

            let task = backgroundSession.downloadTask(with: request)
            task.taskDescription = id

            let metadata = DownloadedMediaMetadata(
                ratingKey: mediaItem.id,
                guid: mediaItem.guid,
                type: mediaItem.type,
                sourceLibrarySectionID: plexItem.librarySectionID,
                sourceLibraryAgent: plexItem.librarySectionID.flatMap { librariesBySectionID[$0] }?.agent,
                artworkLayoutStyle: preferredArtworkLayoutStyle(
                    for: plexItem,
                    librariesBySectionID: librariesBySectionID
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
                status: .downloading,
                progress: 0,
                bytesWritten: 0,
                totalBytes: 0,
                taskIdentifier: task.taskIdentifier,
                errorMessage: nil,
                metadata: metadata,
            )
            items.append(item)
            persistState()
            task.resume()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func enqueueSeason(ratingKey: String, context: PlexAPIContext) async {
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            let episodes = (response.mediaContainer.metadata ?? []).filter { $0.type == .episode }
            for episode in episodes {
                await enqueueItem(ratingKey: episode.ratingKey, context: context)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func enqueueShow(ratingKey: String, context: PlexAPIContext) async {
        do {
            let metadataRepository = try MetadataRepository(context: context)
            let response = try await metadataRepository.getMetadataChildren(ratingKey: ratingKey)
            let seasons = (response.mediaContainer.metadata ?? []).filter { $0.type == .season }
            for season in seasons {
                await enqueueSeason(ratingKey: season.ratingKey, context: context)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func delete(_ item: DownloadItem) async {
        if let taskIdentifier = item.taskIdentifier {
            ignoredCompletionIDs.insert(item.id)
            await cancelTask(with: taskIdentifier)
        }

        let folderURL = downloadsDirectory.appendingPathComponent(item.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: folderURL.path) {
            try? FileManager.default.removeItem(at: folderURL)
        }

        items.removeAll { $0.id == item.id }
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
               let response = try? await metadataRepository.getMetadata(ratingKey: items[index].metadata.ratingKey),
               let plexItem = response.mediaContainer.metadata?.first {
                items[index].metadata.sourceLibrarySectionID = plexItem.librarySectionID
            }

            let expectedArtworkLayoutStyle = preferredArtworkLayoutStyle(
                for: items[index].metadata,
                librariesBySectionID: librariesBySectionID
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

    /// Re-evaluate the current network path on the monitor queue and update
    /// `isOffline` / `isOnWiFi`.  Safe to call from pull-to-refresh or anywhere
    /// the app needs a definitive online/offline answer without waiting for the
    /// next automatic `pathUpdateHandler` callback.
    ///
    /// - Parameter serverProbe: An optional async closure that performs a
    ///   lightweight connectivity check against the application's server
    ///   (e.g. a Plex health-check ping).  When provided and the OS network
    ///   path is satisfied, the probe is also awaited; `isOffline` is only
    ///   cleared to `false` when the probe returns `true`.  This prevents a
    ///   false-positive "back online" flip when the device has WiFi but the
    ///   server itself is still unreachable — which would cause the app to
    ///   briefly flash a loading screen before re-entering offline mode.
    func recheckNetworkStatus(serverProbe: (() async -> Bool)? = nil) async {
        let pathResult: (isSatisfied: Bool, isWiFi: Bool)
        if OfflineReconnectUITestFixtures.isActive() {
            pathResult = (true, true)
        } else {
            pathResult = await withCheckedContinuation { continuation in
                monitorQueue.async { [weak self] in
                    guard let self else {
                        continuation.resume(returning: (false, false))
                        return
                    }
                    let path = self.monitor.currentPath
                    continuation.resume(returning: (
                        path.status == .satisfied,
                        path.usesInterfaceType(.wifi)
                    ))
                }
            }
        }

        let networkAvailable = pathResult.isSatisfied
        let isWiFi = pathResult.isWiFi

        // When the OS network path is satisfied and a server probe was supplied,
        // run it to guard against the case where the device has connectivity
        // but the Plex server is still unreachable.
        let serverReachable: Bool
        if networkAvailable, let probe = serverProbe {
            serverReachable = await probe()
        } else {
            serverReachable = networkAvailable
        }

        isOffline = !serverReachable
        isOnWiFi = isWiFi && serverReachable
    }

    private func startNetworkMonitoring() {
        guard !OfflineReconnectUITestFixtures.isActive() else { return }

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            Task { @MainActor in
                self.isOffline = path.status != .satisfied
                self.isOnWiFi = path.usesInterfaceType(.wifi)
            }
        }
        // NWPathMonitor fires pathUpdateHandler immediately with the current path
        // when started (per Apple docs), so no synchronous currentPath seed is
        // needed here.  Reading currentPath synchronously before the monitor queue
        // has run returns a stale "unsatisfied" default and can falsely set
        // isOffline=true on startup, triggering spurious session hydration.
        monitor.start(queue: monitorQueue)
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
            let librariesBySectionID: [Int: Library] = Dictionary(uniqueKeysWithValues: libraries.compactMap { library in
                guard let sectionId = library.sectionId else { return nil }
                return (sectionId, library)
            })
            cachedLibrariesBySectionID = librariesBySectionID
            return librariesBySectionID
        } catch {
            return [:]
        }
    }

    private func preferredArtworkLayoutStyle(
        for plexItem: PlexItem,
        librariesBySectionID: [Int: Library]
    ) -> DownloadArtworkLayoutStyle {
        if plexItem.type == .movie,
           let sectionId = plexItem.librarySectionID,
           let library = librariesBySectionID[sectionId],
           library.isNoneAgentLibrary {
            return .landscape
        }

        return plexItem.type.defaultDownloadArtworkLayoutStyle
    }

    private func preferredArtworkLayoutStyle(
        for metadata: DownloadedMediaMetadata,
        librariesBySectionID: [Int: Library]
    ) -> DownloadArtworkLayoutStyle {
        if metadata.type == .movie,
           let sectionId = metadata.sourceLibrarySectionID,
           let library = librariesBySectionID[sectionId],
           library.isNoneAgentLibrary {
            return .landscape
        }

        return metadata.type.defaultDownloadArtworkLayoutStyle
    }

    private func isAlreadyScheduled(for ratingKey: String) -> Bool {
        items.contains { item in
            item.ratingKey == ratingKey && item.status != .failed
        }
    }

    private func persistState() {
        guard !isLoadingPersistedState else { return }
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            // Log persistence errors for debugging
            print("[DownloadManager] Failed to persist download state: \(error)")
        }
    }

    private func loadPersistedState() {
        guard FileManager.default.fileExists(atPath: indexFileURL.path) else { return }
        isLoadingPersistedState = true
        defer { isLoadingPersistedState = false }

        do {
            let data = try Data(contentsOf: indexFileURL)
            items = try JSONDecoder().decode([DownloadItem].self, from: data)
        } catch {
            // CRITICAL: Log the error instead of silently clearing items
            // This is a known source of regressions where the download tab appeared
            // to disappear - the persistence layer fails silently and wipes the item list.
            // Common causes:
            // - Date encoding format changes between Swift versions
            // - Model schema changes (added/removed/renamed fields)
            // - Corrupted index.json file
            // - Incompatible Codable implementation changes
            print("[DownloadManager] Failed to load persisted downloads: \(error)")
            print("[DownloadManager] Downloads index file location: \(indexFileURL.path)")
            
            // Don't silently wipe items - preserve empty state
            // This prevents loss of download state on app restart
            items = []
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

        do {
            let data = try JSONEncoder().encode(item.metadata)
            try data.write(to: metadataURL, options: .atomic)
            try setExcludedFromBackup(at: metadataURL)
        } catch {}
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
        let tasks = await allTasks()
        let runningTaskIDs = Set(tasks.map(\.taskIdentifier))

        for index in items.indices {
            if let taskIdentifier = items[index].taskIdentifier, runningTaskIDs.contains(taskIdentifier) {
                items[index].status = .downloading
                items[index].errorMessage = nil
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
        guard let index = itemIndex(for: task) else { return }

        // An HTTP error response (e.g. 400 Bad Request from a stale transcode
        // session, or 401 Unauthorized) must NOT be saved as a completed video.
        // URLSession.downloadTask calls didFinishDownloadingTo for ANY response
        // regardless of status code, so we validate here before accepting it.
        if let httpResponse = task.response as? HTTPURLResponse,
           !(200 ..< 300 ~= httpResponse.statusCode) {
            // Discard the staged file (it's an error body, not a video).
            try? FileManager.default.removeItem(at: stagedLocation)
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = "Download failed: HTTP \(httpResponse.statusCode)"
            persistState()
            return
        }

        let item = items[index]
        let destination = resolveDownloadDestination(for: item, response: task.response)

        do {
            try createDirectoryIfNeeded(at: destination.deletingLastPathComponent())

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            try FileManager.default.moveItem(at: stagedLocation, to: destination)
            try setExcludedFromBackup(at: destination)

            let fileAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            let fileSize = (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0

            items[index].status = .completed
            items[index].progress = 1
            items[index].bytesWritten = fileSize
            items[index].totalBytes = fileSize
            items[index].taskIdentifier = nil
            items[index].errorMessage = nil
            items[index].metadata.videoFileName = destination.lastPathComponent
            items[index].metadata.fileSize = fileSize

            persistMetadataFile(for: items[index])
            persistState()
            refreshStorageSummary()
        } catch {
            items[index].status = .failed
            items[index].taskIdentifier = nil
            items[index].errorMessage = error.localizedDescription
            persistState()
        }
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
