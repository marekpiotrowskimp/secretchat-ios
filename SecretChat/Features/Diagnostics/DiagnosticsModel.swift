import Foundation
import GemmaKit
import Observation
import Speech
import SwiftData
import Synchronization

/// On-device measurements: memory, speed, context fill and sustained (thermal) behaviour.
/// Uses the app's shared engine. Every log line is also appended to Documents/diagnostics.log so
/// results can be pulled from the device (`scripts/device.sh pull-log`).
@Observable
final class DiagnosticsModel {
    private(set) var running: String?
    private(set) var log: [String] = []
    private(set) var footprint: UInt64 = 0
    private(set) var available: UInt64?
    private(set) var thermal = "—"

    private let app: AppModel
    private var task: Task<Void, Never>?

    init(app: AppModel) {
        self.app = app
        refreshMetrics()
    }

    var isRunning: Bool { running != nil }

    func refreshMetrics() {
        footprint = DeviceDiagnostics.physicalFootprint()
        available = DeviceDiagnostics.availableMemory()
        thermal = DeviceDiagnostics.thermalState.label
    }

    // MARK: Tests

    func load() {
        start("Ładowanie") {
            await self.app.unloadEngine()
            self.append("— Ładowanie, kontekst \(self.app.settings.contextLength)…  [\(self.memoryLine())]")
            let clock = ContinuousClock()
            let began = clock.now
            do {
                try await self.app.prepareEngine(needsVision: false)
                self.append(String(format: "Załadowano w %.1f s  [%@]", (clock.now - began).seconds, self.memoryLine()))
            } catch {
                self.append("BŁĄD ładowania: \(error.localizedDescription)  [\(self.memoryLine())]")
            }
        }
    }

    func loadVision() {
        start("Moduł obrazów") {
            do {
                try await self.app.prepareEngine(needsVision: true)
                self.append("Moduł obrazów załadowany  [\(self.memoryLine())]")
            } catch {
                self.append("BŁĄD vision: \(error.localizedDescription)  [\(self.memoryLine())]")
            }
        }
    }

    /// ~500 token prompt + 256 generated tokens, greedy — comparable between runs.
    func runBenchmark() {
        start("Benchmark") {
            let text = String(repeating: Self.benchParagraph + " ", count: 6)
            await self.generate([.user("Streść poniższy tekst w kilku punktach:\n\n\(text)")], sampling: .greedy(maxTokens: 256), label: "bench")
        }
    }

    /// Fills ~85% of the context to measure KV cache memory at the configured size.
    func runContextFill() {
        start("Wypełnianie kontekstu") {
            let ctx = await self.app.engine.contextLength
            let perParagraph = (try? await self.app.engine.countTokens(Self.benchParagraph + " ")) ?? 120
            let count = max(1, Int(Double(ctx) * 0.8) / max(perParagraph, 1))
            let text = String(repeating: Self.benchParagraph + " ", count: count)
            await self.generate([.user("Podsumuj jednym zdaniem:\n\n\(text)")], sampling: .greedy(maxTokens: 64), label: "ctx-fill")
        }
    }

    /// Image prefill using a synthetic photo-sized image.
    func runVisionTest() {
        start("Test obrazu") {
            guard let image = Self.testImage() else { return }
            do { try await self.app.prepareEngine(needsVision: true) } catch {
                self.append("BŁĄD vision: \(error.localizedDescription)")
                return
            }
            await self.generate([.user("Opisz krótko ten obraz.", images: [image])], sampling: .greedy(maxTokens: 64), label: "vision")
        }
    }

    /// Generates continuously for `minutes` to observe thermal throttling and memory stability.
    func runSustained(minutes: Int = 10) {
        start("Test \(minutes) min") {
            let deadline = ContinuousClock.now + .seconds(minutes * 60)
            var round = 0
            while ContinuousClock.now < deadline, !Task.isCancelled {
                round += 1
                await self.generate([.user("Napisz długie opowiadanie o smoku z Wawelu. Wersja \(round).")], sampling: .init(maxTokens: 512), label: "sustained#\(round)")
            }
            self.append("Test ciągły zakończony po \(round) rundach.")
        }
    }

    func cancel() {
        task?.cancel()
        app.engine.stopGeneration()
    }

    // MARK: Helpers

    private func start(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        guard task == nil, !app.isGenerating else { return }
        running = name
        task = Task {
            await work()
            self.task = nil
            self.running = nil
            self.refreshMetrics()
        }
    }

    private func generate(_ messages: [ChatMessage], sampling: SamplingParameters, label: String) async {
        do {
            try await app.prepareEngine(needsVision: messages.contains { !$0.images.isEmpty })
            await app.engine.resetCache()
            app.isGenerating = true
            defer { app.isGenerating = false }
            for try await event in app.engine.chat(ChatRequest(messages: messages, sampling: sampling)) {
                guard case .finished(let result) = event else { continue }
                let s = result.stats
                append(String(
                    format: "[%@] prefill %d tok %.1f tok/s | gen %d tok %.1f tok/s | %@ | peak %@ | %@",
                    label, s.promptTokens, s.prefillTokensPerSecond, s.generatedTokens, s.decodeTokensPerSecond,
                    s.stopReason.rawValue, s.peakFootprintBytes.formattedGB, memoryLine()
                ))
            }
        } catch {
            append("[\(label)] BŁĄD: \(error.localizedDescription)  [\(memoryLine())]")
        }
        refreshMetrics()
    }

    private func memoryLine() -> String {
        refreshMetrics()
        var line = "footprint \(footprint.formattedGB)"
        if let available { line += ", wolne \(available.formattedGB)" }
        return line + ", termika \(thermal)"
    }

    #if DEBUG
    /// `GEMMA_AUTORUN=bench,vision` runs diagnostics right after launch (for `devicectl … --console`).
    static func autorunIfRequested(app: AppModel) async {
        guard let list = ProcessInfo.processInfo.environment["GEMMA_AUTORUN"] else { return }
        // Imported files are verified asynchronously after launch.
        for _ in 0..<600 where !(app.modelsReady && (app.isVisionReady || !list.contains("vision"))) {
            try? await Task.sleep(for: .milliseconds(200))
        }
        print("AUTORUN model=\(app.selectedVariant.id) ready=\(app.modelsReady) vision=\(app.isVisionReady)")
        let model = DiagnosticsModel(app: app)
        for name in list.split(separator: ",") {
            switch name {
            case "bench": model.runBenchmark()
            case "vision": model.runVisionTest()
            case "ctx": model.runContextFill()
            case "memprofile": await model.memoryProfile()
            case "speechlocales": await model.speechLocales()
            case "dictationfile": await model.dictationFromFile()
            case "mic": await model.liveMicrophone()
            case "memory": await model.memoryFlow()
            case "datastats": model.dataStats()
            default: continue
            }
            while model.isRunning { try? await Task.sleep(for: .milliseconds(200)) }
        }
        print("AUTORUN DONE")
    }
    #endif

    /// System-wide wired/free memory across the model lifecycle — the numbers that decide whether the
    /// rest of iOS (display, services) still has room. See PLAN.md "Pamięć wired".
    func memoryProfile() async {
        func snap(_ label: String) {
            append("[mem] \(label): \(DeviceDiagnostics.systemMemory()?.description ?? "?") | app \(DeviceDiagnostics.physicalFootprint().formattedGB)")
        }
        let env = ProcessInfo.processInfo.environment
        append("[mem] variant model=\(app.selectedVariant.id) noResidency=\(env["GGML_METAL_NO_RESIDENCY"] != nil) gpuLayers=\(env["GEMMA_GPU_LAYERS"] ?? "all")")
        await app.unloadEngine()
        try? await Task.sleep(for: .seconds(3))
        snap("before load")
        do { try await app.prepareEngine(needsVision: false) } catch { append("[mem] load failed: \(error)"); return }
        snap("after load")

        // Sample during generation.
        let peak = Mutex<UInt64>(0)
        let sampler = Task.detached {
            while !Task.isCancelled {
                if let w = DeviceDiagnostics.systemMemory()?.wired { peak.withLock { $0 = max($0, w) } }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
        let text = String(repeating: Self.benchParagraph + " ", count: 6)
        await generate([.user("Streść poniższy tekst w kilku punktach:\n\n\(text)")], sampling: .greedy(maxTokens: 256), label: "mem-bench")
        sampler.cancel()
        append("[mem] peak wired during generation: \(peak.withLock { $0 }.formattedGB)")
        try? await Task.sleep(for: .seconds(10)); snap("idle +10s")
        try? await Task.sleep(for: .seconds(50)); snap("idle +60s")
        await app.unloadEngine()
        try? await Task.sleep(for: .seconds(3))
        snap("after unload")
    }

    /// What the app's own store holds (e.g. after moving data from another install).
    func dataStats() {
        let context = SecretChatApp.container.mainContext
        let conversations = (try? context.fetchCount(FetchDescriptor<Conversation>())) ?? -1
        let messages = (try? context.fetchCount(FetchDescriptor<StoredMessage>())) ?? -1
        let memories = (try? context.fetch(FetchDescriptor<MemoryItem>())) ?? []
        append("[data] conversations=\(conversations) messages=\(messages) memories=\(memories.count) \(memories.map(\.name)) model=\(app.selectedVariant.id) ready=\(app.modelsReady) vision=\(app.isVisionReady)")
    }

    /// Long-term memory on the device with the real model, in a throwaway in-memory store: the cost
    /// of the memory prompt on the first message, then save → read in a new conversation → forget.
    func memoryFlow() async {
        let settings = app.settings
        let saved = (settings.memoryEnabled, settings.webSearchEnabled, settings.speechAutoRead)
        defer { (settings.memoryEnabled, settings.webSearchEnabled, settings.speechAutoRead) = saved }
        settings.webSearchEnabled = false
        settings.speechAutoRead = false
        guard let container = try? ModelContainer(for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true)) else {
            append("[memory] no container"); return
        }
        let context = ModelContext(container)
        append("[memory] model=\(app.selectedVariant.id)")

        func ask(_ text: String) async -> StoredMessage? {
            let conversation = Conversation()
            context.insert(conversation)
            let chat = ChatViewModel(conversation: conversation, app: app, context: context)
            chat.draft = text
            let clock = ContinuousClock()
            let began = clock.now
            await chat.send()?.value
            guard let answer = conversation.orderedMessages.last, answer.role == .assistant else {
                append("[memory] \(text.debugDescription) → BŁĄD \(chat.errorMessage ?? "brak odpowiedzi")"); return nil
            }
            let stats = answer.stats.map { String(format: "prompt %d tok (reused %d), prefill %.2f s", $0.promptTokens, $0.reusedTokens, $0.prefillSeconds) } ?? "—"
            append(String(format: "[memory] %@ → %@ | events=%@ | %.1f s total | %@",
                          text.debugDescription, answer.text.debugDescription, "\(answer.memoryEvents.map { "\($0.kind):\($0.name)" })",
                          (clock.now - began).seconds, stats))
            return answer
        }

        // Prompt cost: same first message without and with the memory prompt (different system
        // prompts, so the KV cache can't hide the difference).
        settings.memoryEnabled = false
        _ = await ask("Ile to 2+2? Odpowiedz liczbą.")
        settings.memoryEnabled = true
        _ = await ask("Ile to 2+3? Odpowiedz liczbą.")

        _ = await ask("Zapamiętaj, że mój pies ma na imię Burek i jest jamnikiem.")
        let items = (try? context.fetch(FetchDescriptor<MemoryItem>())) ?? []
        append("[memory] stored: \(items.map { "\($0.name) — \($0.summary) — \($0.content)" })")
        _ = await ask("Jak ma na imię mój pies?")
        _ = await ask("Zapomnij, jak ma na imię mój pies.")
        append("[memory] left after forget: \((try? context.fetchCount(FetchDescriptor<MemoryItem>())) ?? -1)")
    }

    /// Which speech recognition models can transcribe Polish / English on this device, offline.
    func speechLocales() async {
        func ids(_ locales: [Locale]) -> [String] {
            locales.map(\.identifier).filter { $0.hasPrefix("pl") || $0.hasPrefix("en_US") || $0.hasPrefix("en-US") }
        }
        append("[speech] SpeechTranscriber supported=\(ids(await SpeechTranscriber.supportedLocales)) installed=\(ids(await SpeechTranscriber.installedLocales))")
        append("[speech] DictationTranscriber supported=\(ids(await DictationTranscriber.supportedLocales)) installed=\(ids(await DictationTranscriber.installedLocales))")
        for id in ["pl-PL", "en-US"] {
            let r = SFSpeechRecognizer(locale: Locale(identifier: id))
            append("[speech] SFSpeechRecognizer \(id): available=\(r?.isAvailable ?? false) onDevice=\(r?.supportsOnDeviceRecognition ?? false)")
        }
    }

    /// Real microphone for 3 s through DictationService (reproduces live dictation).
    func liveMicrophone() async {
        append("[mic] starting")
        await app.dictation.start { _ in }
        append("[mic] state=\(app.dictation.state)")
        let seconds = Double(ProcessInfo.processInfo.environment["GEMMA_MIC_SECONDS"] ?? "3") ?? 3
        try? await Task.sleep(for: .seconds(seconds))
        let final = await app.dictation.finish()
        append("[mic] finished text=\(final.text.debugDescription) level=\(app.dictation.level)")
    }

    /// Transcribes Documents/dictation-test.aiff with the dictation pipeline (Polish check on device).
    func dictationFromFile() async {
        let url = URL.documentsDirectory.appending(path: "dictation-test.aiff")
        guard FileManager.default.fileExists(atPath: url.path) else { append("[dictation] no test file"); return }
        guard let locale = await DictationSession.supportedLocale(for: app.dictation.preferredLocale) else {
            append("[dictation] locale unsupported: \(app.dictation.preferredLocale.identifier)"); return
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let text = try await DictationSession.transcribe(file: url, locale: locale)
            let parsed = DictationCommand.extract(from: text)
            append("[dictation] \(locale.identifier) in \(String(format: "%.1f", (clock.now - start).seconds)) s: \(text.debugDescription) → text=\(parsed.text.debugDescription) command=\(String(describing: parsed.command))")
        } catch {
            append("[dictation] error: \(error)")
        }
    }

    private func append(_ line: String) {
        let stamped = "\(Date.now.formatted(date: .omitted, time: .standard))  \(line)"
        print("DIAG", stamped)
        log.append(stamped)
        Self.appendToFile(stamped)
    }

    private static func appendToFile(_ line: String) {
        let url = URL.documentsDirectory.appending(path: "diagnostics.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }

    private static func testImage() -> Data? {
        let size = CGSize(width: 1200, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor.systemYellow.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 450, y: 100, width: 300, height: 300))
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 600, width: 1200, height: 300))
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    private static let benchParagraph = """
    Kraków jest jednym z najstarszych miast w Polsce, a jego historia sięga co najmniej VII wieku. \
    Przez stulecia był stolicą kraju i siedzibą królów, którzy koronowali się w katedrze na Wawelu. \
    Stare Miasto, z Rynkiem Głównym, Sukiennicami i Kościołem Mariackim, zostało wpisane na listę \
    światowego dziedzictwa UNESCO jako jeden z pierwszych obiektów na świecie.
    """
}

import UIKit

private extension Duration {
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
