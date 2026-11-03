import Foundation
import GemmaKit
import Observation
import UIKit

/// App-wide state: model files, the inference engine and its lifecycle.
@Observable
final class AppModel {
    enum EngineState: Equatable {
        case idle
        case loading(Double)
        case ready
        case failed(String)
    }

    /// One background URLSession per identifier — the store must be a process-wide singleton.
    static let sharedStore: ModelStore = {
        #if DEBUG
        // Tests/simulator: point the store at a folder with already-downloaded model files.
        if let dir = ProcessInfo.processInfo.environment["GEMMA_MODEL_DIR"] {
            return ModelStore(directory: URL(filePath: dir, directoryHint: .isDirectory), assets: ModelCatalog.allAssets, configuration: .default)
        }
        #endif
        return ModelStore(assets: ModelCatalog.allAssets)
    }()

    /// The real device, or (DEBUG) a simulated one: GEMMA_DEVICE_RAM_GB=8 GEMMA_DEVICE_NAME="iPhone 16".
    static var currentDevice: DeviceProfile {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let ram = env["GEMMA_DEVICE_RAM_GB"].flatMap(Int.init) {
            return DeviceProfile(ramGB: ram, name: env["GEMMA_DEVICE_NAME"])
        }
        #endif
        return .current
    }

    let store: ModelStore
    let engine = LlamaEngine()
    let settings: AppSettings
    let device: DeviceProfile
    let speech: SpeechReader
    let dictation: DictationService

    private(set) var assetStates: [String: AssetState] = [:]
    private(set) var engineState: EngineState = .idle
    private(set) var thermalState = ProcessInfo.processInfo.thermalState
    /// Set while a chat turn runs, so settings changes don't reload the engine underneath it.
    var isGenerating = false

    private var loadedContextLength: Int?
    private var loadedVariantID: String?
    private var loadTask: Task<Void, Error>?
    private var observers: [NSObjectProtocol] = []
    private let memoryPressure = DispatchSource.makeMemoryPressureSource(eventMask: .critical, queue: .main)
    /// Set when generation was stopped to protect the system; shown in the chat.
    private(set) var memoryPressureStops = 0

    init(store: ModelStore = AppModel.sharedStore, settings: AppSettings = AppSettings(), device: DeviceProfile = AppModel.currentDevice) {
        self.store = store
        self.settings = settings
        self.device = device
        self.speech = SpeechReader(settings: settings)
        self.dictation = DictationService(settings: settings)
        #if DEBUG
        dictation.fakeAudio = ProcessInfo.processInfo.environment["GEMMA_FAKE_DICTATION"] == "1"
        #endif
        for asset in store.assets { assetStates[asset.id] = store.state(of: asset) }
        store.observe { [weak self] id, state in
            Task { @MainActor in self?.assetStates[id] = state }
        }
        // Model files dropped into Documents (Files app, Finder, devicectl) are picked up on launch.
        store.importFiles(from: URL.documentsDirectory)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.handleMemoryWarning() }
        })
        // While the GPU computes, the model's weights are wired (12B: ~7.6 GB on a 12 GB phone). If the
        // whole system runs out of memory, stop generating at once rather than starve the display and
        // system services (which led to freezes and a watchdog restart).
        memoryPressure.setEventHandler { [weak self] in
            Task { @MainActor in self?.handleCriticalMemoryPressure() }
        }
        memoryPressure.activate()
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermalState = ProcessInfo.processInfo.thermalState }
        })
    }

    // MARK: Model choice

    /// The model the user picked, or the best one for this phone.
    var selectedVariant: ModelVariant {
        ModelCatalog.variant(id: settings.selectedModelID) ?? recommendedVariant
    }

    var recommendedVariant: ModelVariant { ModelCatalog.recommended(for: device) }

    func fit(of variant: ModelVariant) -> ModelFit { ModelCatalog.fit(of: variant, on: device) }

    /// Switches the active model. The engine reloads lazily on the next message.
    func select(_ variant: ModelVariant) {
        guard variant != selectedVariant || settings.selectedModelID == nil else { return }
        settings.selectedModelID = variant.id
    }

    // MARK: Model files

    /// Chat is possible once the selected language model is on disk; vision is optional.
    var modelsReady: Bool { isDownloaded(selectedVariant) }
    var isVisionReady: Bool { state(of: selectedVariant.vision).isReady }

    func isDownloaded(_ variant: ModelVariant) -> Bool { state(of: variant.model).isReady }
    func state(of asset: ModelAsset) -> AssetState { assetStates[asset.id] ?? .missing }

    /// Bytes on disk for a variant's downloaded files.
    func storedBytes(of variant: ModelVariant) -> Int64 {
        variant.assets.filter { state(of: $0).isReady }.reduce(0) { $0 + $1.expectedBytes }
    }

    func download(_ variant: ModelVariant, includeVision: Bool) {
        var assets = [variant.model]
        if includeVision { assets.append(variant.vision) }
        for asset in assets where !(state(of: asset).isReady || state(of: asset).isActive) {
            store.download(asset, allowsCellular: settings.allowCellularDownload)
        }
    }

    func downloadVision() {
        download(selectedVariant, includeVision: true)
    }

    func pauseDownloads(of variant: ModelVariant) {
        variant.assets.forEach(store.pause)
    }

    func delete(_ variant: ModelVariant) async {
        // Deleting a memory-mapped file under a loaded model crashes with SIGBUS on the next read, so
        // always release the engine first (also covers a load still in progress).
        if let loadTask { _ = try? await loadTask.value }
        await unloadEngine()
        variant.assets.forEach(store.delete)
        if settings.selectedModelID == variant.id {
            // Fall back to another downloaded model, if any.
            settings.selectedModelID = ModelCatalog.variants.first { $0 != variant && isDownloaded($0) }?.id
        }
    }

    // MARK: Internet

    /// Name shown in the consent dialog: where the query will be sent first.
    var searchEngineName: String {
        settings.searchProvider == .brave && !settings.braveAPIKey.isEmpty ? "Brave Search" : "DuckDuckGo"
    }

    /// Search used after the user approved a query: Brave (if a key is set) → DuckDuckGo → Wikipedia.
    var researcher: WebResearching {
        #if DEBUG
        if let override = researcherOverride { return override }
        if ProcessInfo.processInfo.environment["GEMMA_FAKE_WEB"] == "1" { return FakeWebResearcher() }
        #endif
        var providers: [WebSearchProvider] = []
        if settings.searchProvider == .brave, !settings.braveAPIKey.isEmpty {
            providers.append(BraveSearch(apiKey: settings.braveAPIKey))
        }
        let language = Locale.preferredLanguages.first.map { Locale(identifier: $0).language.languageCode?.identifier ?? "pl" } ?? "pl"
        providers.append(DuckDuckGoSearch(region: language == "pl" ? "pl-pl" : "wt-wt"))
        providers.append(WikipediaSearch(language: language))
        return WebResearcher(search: FallbackSearch(providers))
    }

    #if DEBUG
    /// Tests inject a fake researcher here.
    var researcherOverride: WebResearching?
    #endif

    // MARK: Engine

    /// Loads the model (or reloads it after a context-length change) and, if needed, the vision projector.
    func prepareEngine(needsVision: Bool) async throws {
        if let loadTask { try await loadTask.value }
        let wanted = settings.contextLength
        let variant = selectedVariant
        let isLoaded = await engine.isLoaded
        if loadedContextLength != wanted || loadedVariantID != variant.id || !isLoaded {
            let task = Task { try await load(variant, contextLength: wanted) }
            loadTask = task
            defer { loadTask = nil }
            try await task.value
        }
        if needsVision, await !engine.isVisionLoaded {
            guard isVisionReady else { throw EngineError.visionNotLoaded }
            try await engine.loadVision(mmprojURL: store.fileURL(of: variant.vision))
        }
    }

    private func load(_ variant: ModelVariant, contextLength: Int) async throws {
        engineState = .loading(0)
        do {
            var configuration = EngineConfiguration(contextLength: contextLength)
            #if DEBUG
            if let layers = ProcessInfo.processInfo.environment["GEMMA_GPU_LAYERS"].flatMap(Int32.init) {
                configuration.gpuLayers = layers
            }
            #endif
            try await engine.load(
                modelURL: store.fileURL(of: variant.model),
                configuration: configuration
            ) { progress in
                Task { @MainActor [weak self] in
                    if case .loading = self?.engineState { self?.engineState = .loading(progress) }
                }
            }
            loadedContextLength = contextLength
            loadedVariantID = variant.id
            engineState = .ready
        } catch {
            loadedContextLength = nil
            loadedVariantID = nil
            engineState = .failed(error.localizedDescription)
            throw error
        }
    }

    func unloadEngine() async {
        await engine.unload()
        loadedContextLength = nil
        loadedVariantID = nil
        engineState = .idle
    }

    /// The engine drops a model whose GPU backend failed; reflect that so the status is accurate
    /// and the next message reloads it.
    func syncEngineState() async {
        if await !engine.isLoaded, engineState == .ready {
            loadedVariantID = nil
            loadedContextLength = nil
            engineState = .idle
        }
    }

    /// Frees the vision projector first; the main model is only dropped when idle.
    func handleMemoryWarning() async {
        await engine.unloadVision()
    }

    func handleCriticalMemoryPressure() {
        guard isGenerating else { return }
        memoryPressureStops += 1
        engine.stopGeneration()
        Task { await engine.unloadVision() }
    }

    /// GPU work is not allowed in the background — finish the current answer gracefully.
    func enterBackground() {
        engine.stopGeneration()
    }
}
