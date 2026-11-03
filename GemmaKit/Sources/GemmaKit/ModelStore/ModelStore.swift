import CryptoKit
import Foundation
import Synchronization

public enum AssetState: Sendable, Equatable {
    case missing
    /// Paused/failed download that can resume where it stopped.
    case paused(received: Int64)
    case downloading(received: Int64, total: Int64)
    case verifying
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
    public var isActive: Bool {
        switch self { case .downloading, .verifying: true; default: false }
    }
}

/// Downloads, verifies and stores model files.
///
/// Uses a background `URLSession` so a 7 GB download continues while the app is suspended.
/// A file counts as ready only after its SHA-256 matched; the verified hash is cached in a sidecar
/// file so the 7 GB file is not re-hashed on every launch.
public final class ModelStore: NSObject, @unchecked Sendable {
    public static let backgroundSessionID = "com.marekpiotrowski.SecretChat.model-download"

    public let directory: URL
    public let assets: [ModelAsset]

    private let states: Mutex<[String: AssetState]>
    private let handlers = Mutex<[UUID: @Sendable (String, AssetState) -> Void]>([:])
    private let backgroundCompletion = Mutex<(@Sendable () -> Void)?>(nil)
    private var session: URLSession!

    /// Default location: Application Support/Models (not visible in Files, excluded from backup).
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }

    public init(
        directory: URL = ModelStore.defaultDirectory,
        assets: [ModelAsset] = ModelCatalog.allAssets,
        configuration: URLSessionConfiguration? = nil
    ) {
        self.directory = directory
        self.assets = assets
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Self.excludeFromBackup(directory)

        var initial: [String: AssetState] = [:]
        for asset in assets {
            initial[asset.id] = Self.initialState(of: asset, in: directory)
        }
        states = Mutex(initial)
        super.init()

        // A finished download whose verification was interrupted (app killed or crashed): verify it
        // again instead of downloading gigabytes from scratch.
        for asset in assets where state(of: asset) != .ready {
            let size = (try? FileManager.default.attributesOfItem(atPath: partialURL(asset).path)[.size] as? Int64) ?? nil
            if size == asset.expectedBytes { verifyAndInstall(asset) }
        }

        let config = configuration ?? {
            let c = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionID)
            c.isDiscretionary = false
            c.sessionSendsLaunchEvents = true
            c.timeoutIntervalForResource = 60 * 60 * 24
            return c
        }()
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Re-attach to downloads that kept running while the app was not alive.
        session.getAllTasks { tasks in
            for task in tasks where task.state == .running {
                guard let id = task.taskDescription else { continue }
                self.set(id, .downloading(received: task.countOfBytesReceived, total: max(task.countOfBytesExpectedToReceive, 0)))
            }
        }
    }

    // MARK: Queries

    public func state(of asset: ModelAsset) -> AssetState { states.withLock { $0[asset.id] ?? .missing } }
    public func fileURL(of asset: ModelAsset) -> URL { directory.appending(path: asset.fileName) }
    public var allReady: Bool { assets.allSatisfy { state(of: $0).isReady } }

    /// Bytes still to download for assets that are not ready.
    public var remainingBytes: Int64 {
        assets.filter { !state(of: $0).isReady }.reduce(0) { total, asset in
            if case .paused(let received) = state(of: asset) { return total + asset.expectedBytes - received }
            return total + asset.expectedBytes
        }
    }

    public static func availableDiskSpace(at url: URL = URL.applicationSupportDirectory) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// Subscribe to state changes (called on an arbitrary queue). Returns a token for `removeObserver`.
    @discardableResult
    public func observe(_ handler: @escaping @Sendable (String, AssetState) -> Void) -> UUID {
        let id = UUID()
        handlers.withLock { $0[id] = handler }
        return id
    }

    public func removeObserver(_ id: UUID) { handlers.withLock { _ = $0.removeValue(forKey: id) } }

    // MARK: Actions

    public func download(_ asset: ModelAsset, allowsCellular: Bool = true) {
        guard !state(of: asset).isActive, !state(of: asset).isReady else { return }
        var request = URLRequest(url: asset.remoteURL)
        request.allowsCellularAccess = allowsCellular

        let task: URLSessionDownloadTask
        if let resume = try? Data(contentsOf: resumeDataURL(asset)) {
            task = session.downloadTask(withResumeData: resume)
            try? FileManager.default.removeItem(at: resumeDataURL(asset))
        } else {
            task = session.downloadTask(with: request)
        }
        task.taskDescription = asset.id
        task.countOfBytesClientExpectsToReceive = asset.expectedBytes
        set(asset.id, .downloading(received: 0, total: asset.expectedBytes))
        task.resume()
    }

    /// Pauses a running download, keeping resume data so it continues later.
    public func pause(_ asset: ModelAsset) {
        session.getAllTasks { tasks in
            for case let task as URLSessionDownloadTask in tasks where task.taskDescription == asset.id {
                task.cancel { data in
                    if let data { try? data.write(to: self.resumeDataURL(asset)) }
                    self.set(asset.id, data == nil ? .missing : .paused(received: task.countOfBytesReceived))
                }
            }
        }
    }

    public func delete(_ asset: ModelAsset) {
        pause(asset)
        for url in [fileURL(of: asset), verifiedMarkerURL(asset), resumeDataURL(asset), partialURL(asset)] {
            try? FileManager.default.removeItem(at: url)
        }
        set(asset.id, .missing)
    }

    /// Moves model files placed in `folder` (e.g. Documents via Files app / devicectl) into the store
    /// and verifies them. Returns the assets that were found.
    @discardableResult
    public func importFiles(from folder: URL) -> [ModelAsset] {
        var found: [ModelAsset] = []
        for asset in assets where !state(of: asset).isReady {
            let candidate = folder.appending(path: asset.fileName)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            try? FileManager.default.removeItem(at: partialURL(asset))
            guard (try? FileManager.default.moveItem(at: candidate, to: partialURL(asset))) != nil else { continue }
            found.append(asset)
            verifyAndInstall(asset)
        }
        return found
    }

    /// Hand over the completion handler from `application(_:handleEventsForBackgroundURLSession:)`.
    public func setBackgroundCompletionHandler(_ handler: @escaping @Sendable () -> Void) {
        backgroundCompletion.withLock { $0 = handler }
    }

    // MARK: Verification

    public static func sha256(of url: URL, chunkSize: Int = 8 << 20) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        // Each read returns an autoreleased buffer. Without a pool per chunk they all stay alive until
        // the loop ends — hashing the 6.7 GB model then needs 6.7 GB of RAM and iOS kills the app.
        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func verifyAndInstall(_ asset: ModelAsset) {
        set(asset.id, .verifying)
        let partial = partialURL(asset)
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            do {
                let size = (try fm.attributesOfItem(atPath: partial.path)[.size] as? Int64) ?? -1
                guard size == asset.expectedBytes else {
                    throw StoreError.sizeMismatch(expected: asset.expectedBytes, actual: size)
                }
                let hash = try Self.sha256(of: partial)
                guard hash == asset.sha256 else { throw StoreError.checksumMismatch }
                let final = self.fileURL(of: asset)
                try? fm.removeItem(at: final)
                try fm.moveItem(at: partial, to: final)
                try hash.write(to: self.verifiedMarkerURL(asset), atomically: true, encoding: .utf8)
                self.set(asset.id, .ready)
            } catch {
                try? fm.removeItem(at: partial)
                self.set(asset.id, .failed(error.localizedDescription))
            }
        }
    }

    enum StoreError: LocalizedError {
        case sizeMismatch(expected: Int64, actual: Int64)
        case checksumMismatch
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .sizeMismatch(let e, let a): String(localized: "Nieprawidłowy rozmiar pliku (\(a) zamiast \(e) B).", bundle: .module)
            case .checksumMismatch: String(localized: "Suma kontrolna się nie zgadza — plik uszkodzony.", bundle: .module)
            case .httpStatus(let code): String(localized: "Serwer zwrócił błąd HTTP \(code).", bundle: .module)
            }
        }
    }

    // MARK: Helpers

    private static func initialState(of asset: ModelAsset, in directory: URL) -> AssetState {
        let file = directory.appending(path: asset.fileName)
        let marker = directory.appending(path: asset.fileName + ".sha256")
        if FileManager.default.fileExists(atPath: file.path),
           (try? String(contentsOf: marker, encoding: .utf8)) == asset.sha256 {
            return .ready
        }
        let resume = directory.appending(path: asset.id + ".resume")
        if FileManager.default.fileExists(atPath: resume.path) { return .paused(received: 0) }
        return .missing
    }

    private func set(_ id: String, _ state: AssetState) {
        states.withLock { $0[id] = state }
        let observers = handlers.withLock { Array($0.values) }
        observers.forEach { $0(id, state) }
    }

    private func asset(for task: URLSessionTask) -> ModelAsset? {
        assets.first { $0.id == task.taskDescription }
    }

    private func partialURL(_ asset: ModelAsset) -> URL { directory.appending(path: asset.fileName + ".download") }
    private func verifiedMarkerURL(_ asset: ModelAsset) -> URL { directory.appending(path: asset.fileName + ".sha256") }
    private func resumeDataURL(_ asset: ModelAsset) -> URL { directory.appending(path: asset.id + ".resume") }

    private static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

extension ModelStore: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let asset = asset(for: downloadTask) else { return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : asset.expectedBytes
        set(asset.id, .downloading(received: totalBytesWritten, total: total))
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let asset = asset(for: downloadTask) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            set(asset.id, .failed(StoreError.httpStatus(http.statusCode).localizedDescription))
            return
        }
        // The temporary file is deleted when this method returns — move it synchronously.
        let partial = partialURL(asset)
        try? FileManager.default.removeItem(at: partial)
        do {
            try FileManager.default.moveItem(at: location, to: partial)
        } catch {
            set(asset.id, .failed(error.localizedDescription))
            return
        }
        verifyAndInstall(asset)
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let asset = asset(for: task) else { return }
        let nsError = error as NSError
        if let resume = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
            try? resume.write(to: resumeDataURL(asset))
        }
        if nsError.code == NSURLErrorCancelled { return } // pause() sets the state itself
        let hasResume = FileManager.default.fileExists(atPath: resumeDataURL(asset).path)
        set(asset.id, hasResume ? .paused(received: task.countOfBytesReceived) : .failed(error.localizedDescription))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let handler = backgroundCompletion.withLock { h -> (@Sendable () -> Void)? in
            defer { h = nil }
            return h
        }
        DispatchQueue.main.async { handler?() }
    }
}
