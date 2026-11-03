import CryptoKit
import Foundation
import Testing
@testable import GemmaKit

/// ModelStore against local `file://` sources (no network): download → verify → ready, checksum
/// failure, persisted verification and import from a folder.
@Suite(.serialized)
struct ModelStoreTests {
    let root: URL
    let source: URL
    let payload: Data

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ModelStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        payload = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        source = root.appending(path: "source.gguf")
        try payload.write(to: source)
    }

    private func asset(sha: String? = nil, size: Int64? = nil) -> ModelAsset {
        ModelAsset(
            id: "test-asset", fileName: "model.gguf", remoteURL: source,
            expectedBytes: size ?? Int64(payload.count),
            sha256: sha ?? SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func makeStore(_ asset: ModelAsset) -> ModelStore {
        ModelStore(directory: root.appending(path: "store"), assets: [asset], configuration: .default)
    }

    /// Waits until the asset reaches a terminal state.
    private func waitForTerminal(_ store: ModelStore, _ asset: ModelAsset) async throws -> AssetState {
        for _ in 0..<200 {
            let state = store.state(of: asset)
            switch state {
            case .ready, .failed: return state
            default: try await Task.sleep(for: .milliseconds(50))
            }
        }
        return store.state(of: asset)
    }

    @Test func sha256MatchesCryptoKit() throws {
        let expected = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        #expect(try ModelStore.sha256(of: source, chunkSize: 1 << 20) == expected)
    }

    @Test func downloadVerifiesAndInstalls() async throws {
        let asset = asset()
        let store = makeStore(asset)
        #expect(store.state(of: asset) == .missing)
        store.download(asset)
        #expect(try await waitForTerminal(store, asset) == .ready)
        #expect(try Data(contentsOf: store.fileURL(of: asset)) == payload)

        // A fresh store finds the verified file without re-downloading.
        #expect(makeStore(asset).state(of: asset) == .ready)

        store.delete(asset)
        #expect(store.state(of: asset) == .missing)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(of: asset).path))
    }

    @Test func checksumMismatchFails() async throws {
        let asset = asset(sha: String(repeating: "0", count: 64))
        let store = makeStore(asset)
        store.download(asset)
        guard case .failed = try await waitForTerminal(store, asset) else {
            Issue.record("expected failure"); return
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(of: asset).path))
    }

    @Test func sizeMismatchFails() async throws {
        let asset = asset(size: 123)
        let store = makeStore(asset)
        store.download(asset)
        guard case .failed = try await waitForTerminal(store, asset) else {
            Issue.record("expected failure"); return
        }
    }

    @Test func importsFromFolder() async throws {
        let asset = asset()
        let inbox = root.appending(path: "inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try payload.write(to: inbox.appending(path: asset.fileName))

        let store = makeStore(asset)
        #expect(store.importFiles(from: inbox) == [asset])
        #expect(try await waitForTerminal(store, asset) == .ready)
        #expect(!FileManager.default.fileExists(atPath: inbox.appending(path: asset.fileName).path))
    }

    @Test func observersReceiveProgress() async throws {
        let asset = asset()
        let store = makeStore(asset)
        let seen = Mutex<[AssetState]>([])
        store.observe { _, state in seen.withLock { $0.append(state) } }
        store.download(asset)
        _ = try await waitForTerminal(store, asset)
        let states = seen.withLock { $0 }
        #expect(states.contains(.verifying))
        #expect(states.last == .ready)
    }

    /// Real download of the vision projector from Hugging Face (175 MB) + SHA-256. Opt-in: NETWORK_TESTS=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NETWORK_TESTS"] == "1"), .timeLimit(.minutes(10)))
    func downloadsRealAssetFromHuggingFace() async throws {
        let store = ModelStore(directory: root.appending(path: "real"), assets: [ModelCatalog.gemma12B.vision], configuration: .default)
        store.download(ModelCatalog.gemma12B.vision, allowsCellular: true)
        var state = store.state(of: ModelCatalog.gemma12B.vision)
        while state != .ready, !{ if case .failed = state { true } else { false } }() {
            try await Task.sleep(for: .milliseconds(500))
            state = store.state(of: ModelCatalog.gemma12B.vision)
        }
        #expect(state == .ready)
        let size = try FileManager.default.attributesOfItem(atPath: store.fileURL(of: ModelCatalog.gemma12B.vision).path)[.size] as? Int64
        #expect(size == ModelCatalog.gemma12B.vision.expectedBytes)
    }

    /// Regression: hashing used to keep every chunk alive (6.7 GB RAM for the 12B model → jetsam on iPhone).
    @Test func hashingLargeFileUsesConstantMemory() throws {
        let big = root.appending(path: "big.bin")
        FileManager.default.createFile(atPath: big.path, contents: nil)
        let handle = try FileHandle(forWritingTo: big)
        let block = Data(repeating: 0xAB, count: 8 << 20)
        for _ in 0..<192 { try handle.write(contentsOf: block) } // 1.5 GB
        try handle.close()

        // Other suites load models in parallel and move the process footprint by up to a few hundred MB;
        // a real leak grows by the file size (1.5 GB) on every run — so take the smaller of two runs.
        var growths: [Int64] = []
        for _ in 0..<2 {
            let before = DeviceDiagnostics.physicalFootprint()
            _ = try ModelStore.sha256(of: big)
            growths.append(Int64(DeviceDiagnostics.physicalFootprint()) - Int64(before))
        }
        let growth = growths.min()!
        #expect(growth < 750_000_000, "hashing 1.5 GB grew the footprint by \(growth / 1_000_000) MB")
    }

    @Test func resumesVerificationOfCompletedDownload() async throws {
        let asset = asset()
        let dir = root.appending(path: "store")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try payload.write(to: dir.appending(path: asset.fileName + ".download")) // left by an interrupted run

        let store = makeStore(asset)
        #expect(try await waitForTerminal(store, asset) == .ready)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: asset.fileName + ".download").path))
    }

    @Test func catalogIsConsistent() {
        let assets = ModelCatalog.allAssets
        #expect(assets.count == 6)
        #expect(assets.allSatisfy { $0.sha256.count == 64 && $0.expectedBytes > 0 })
        #expect(Set(assets.map(\.fileName)).count == assets.count, "local file names must be unique")
        #expect(Set(assets.map(\.id)).count == assets.count)
        // Largest first: the recommendation relies on this order.
        #expect(ModelCatalog.variants.map(\.requiredRAMGB) == ModelCatalog.variants.map(\.requiredRAMGB).sorted(by: >))
    }
}

import Synchronization
