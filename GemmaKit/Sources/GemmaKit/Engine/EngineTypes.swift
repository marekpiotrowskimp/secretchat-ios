import Foundation

public struct EngineConfiguration: Sendable, Hashable {
    /// KV cache size in tokens.
    public var contextLength: Int
    /// Max tokens submitted to a single `llama_decode` during prefill. Must be ≥ the tokens of one
    /// image, because Gemma's vision tokens use non-causal attention and go in a single ubatch.
    public var batchSize: Int
    /// Layers offloaded to Metal (-1 = all).
    public var gpuLayers: Int32
    /// Memory-map weights so iOS can page them instead of counting them as dirty memory.
    public var useMmap: Bool
    public var threads: Int
    /// 8-bit KV cache halves its memory (0.54 → 0.27 GB at 4K for 12B) with negligible quality loss.
    public var quantizedKVCache: Bool
    /// Upper bound of vision tokens per image. Fewer tokens = smaller GPU buffers while encoding,
    /// which keeps 12B + vision under the iPhone's ~8.6 GB GPU working-set limit.
    public var maxImageTokens: Int

    public init(
        contextLength: Int = 4096,
        batchSize: Int = 512,
        gpuLayers: Int32 = EngineConfiguration.defaultGPULayers,
        useMmap: Bool = true,
        threads: Int = EngineConfiguration.defaultThreads,
        quantizedKVCache: Bool = true,
        maxImageTokens: Int = 256
    ) {
        self.contextLength = contextLength
        self.batchSize = batchSize
        self.gpuLayers = gpuLayers
        self.useMmap = useMmap
        self.threads = threads
        self.quantizedKVCache = quantizedKVCache
        self.maxImageTokens = maxImageTokens
    }
}

public extension EngineConfiguration {
    /// The iOS Simulator's virtualised Metal is unusable for ggml (minutes per token, empty output),
    /// so the simulator runs fully on the host CPU.
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    static var defaultGPULayers: Int32 { isSimulator ? 0 : -1 }

    /// Metal does the heavy lifting on device; CPU threads matter only for sampling/glue.
    /// The iOS Simulator has no Metal backend for ggml, so it gets every core of the host Mac.
    static var defaultThreads: Int {
        #if targetEnvironment(simulator)
        max(1, ProcessInfo.processInfo.activeProcessorCount - 2)
        #else
        max(1, min(4, ProcessInfo.processInfo.activeProcessorCount - 2))
        #endif
    }
}

/// Defaults follow the sampling metadata in the Gemma 4 GGUF (temp 1.0, top-k 64, top-p 0.95).
public struct SamplingParameters: Sendable, Hashable, Codable {
    public var temperature: Float
    public var topK: Int32
    public var topP: Float
    public var minP: Float
    public var maxTokens: Int
    public var seed: UInt32

    public init(
        temperature: Float = 1.0,
        topK: Int32 = 64,
        topP: Float = 0.95,
        minP: Float = 0.0,
        maxTokens: Int = 2048,
        seed: UInt32 = .random(in: 0...UInt32.max)
    ) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.minP = minP
        self.maxTokens = maxTokens
        self.seed = seed
    }

    public static func greedy(maxTokens: Int = 256) -> SamplingParameters {
        .init(temperature: 0, maxTokens: maxTokens, seed: 0)
    }
}

/// A chat turn request: the conversation so far (ending with the new user message).
public struct ChatRequest: Sendable {
    public var messages: [ChatMessage]
    public var systemPrompt: String
    public var enableThinking: Bool
    public var sampling: SamplingParameters
    /// Functions the model may call. Generation stops with `.toolCall` when it does.
    public var tools: [ToolDeclaration]
    /// The unfinished model turn to continue: the previous result's `rawModelTurn` plus the tool
    /// response (see `continuing(after:toolResponse:)`).
    public var continuation: String?
    /// Start the answer with a tool call (the model still picks which tool and its arguments) — for
    /// explicit commands like "Zapamiętaj…" that must never end as a plain "OK, I'll remember".
    public var forceToolCall = false

    public init(
        messages: [ChatMessage], systemPrompt: String = "", enableThinking: Bool = false,
        sampling: SamplingParameters = .init(), tools: [ToolDeclaration] = [], continuation: String? = nil
    ) {
        self.messages = messages
        self.systemPrompt = systemPrompt
        self.enableThinking = enableThinking
        self.sampling = sampling
        self.tools = tools
        self.continuation = continuation
    }

    /// The same request, continued after `result` stopped on a tool call, with the tool's answer.
    public func continuing(after result: GenerationResult, toolName: String, toolResponse: String) -> ChatRequest {
        var next = self
        next.forceToolCall = false
        next.continuation = result.rawModelTurn
            + GemmaPromptBuilder.toolResponse(name: toolName, value: toolResponse)
            // The template reopens the thought channel after a tool response when thinking is on.
            + (enableThinking ? "\(GemmaPromptBuilder.Token.channelStart)thought\n" : "")
        return next
    }
}

public struct GenerationStats: Sendable, Hashable, Codable {
    public enum StopReason: String, Sendable, Codable { case endOfTurn, maxTokens, contextFull, cancelled, toolCall }

    /// Tokens prefilled for this request (only the new part of the conversation).
    public var promptTokens: Int
    /// Tokens already in the KV cache that were reused.
    public var reusedTokens: Int
    public var generatedTokens: Int
    public var prefillSeconds: Double
    public var decodeSeconds: Double
    public var stopReason: StopReason
    public var peakFootprintBytes: UInt64
    /// Oldest messages left out because the conversation no longer fit the context.
    public var droppedMessages: Int = 0
    /// Earlier answers shortened to fit (thinking removed, tool results cut to excerpts) — see `ContextWindow.fitCompacting`.
    public var compactedTurns: Int = 0

    public init(
        promptTokens: Int, reusedTokens: Int, generatedTokens: Int, prefillSeconds: Double,
        decodeSeconds: Double, stopReason: StopReason, peakFootprintBytes: UInt64, droppedMessages: Int = 0
    ) {
        self.promptTokens = promptTokens
        self.reusedTokens = reusedTokens
        self.generatedTokens = generatedTokens
        self.prefillSeconds = prefillSeconds
        self.decodeSeconds = decodeSeconds
        self.stopReason = stopReason
        self.peakFootprintBytes = peakFootprintBytes
        self.droppedMessages = droppedMessages
    }

    public var prefillTokensPerSecond: Double { prefillSeconds > 0 ? Double(promptTokens) / prefillSeconds : 0 }
    public var decodeTokensPerSecond: Double { decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0 }
}

extension GenerationStats {
    private enum CodingKeys: String, CodingKey {
        case promptTokens, reusedTokens, generatedTokens, prefillSeconds, decodeSeconds, stopReason,
             peakFootprintBytes, droppedMessages, compactedTurns
    }

    /// Stats are stored with every answer; fields added later default to 0 so older answers keep theirs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            promptTokens: try c.decode(Int.self, forKey: .promptTokens),
            reusedTokens: try c.decode(Int.self, forKey: .reusedTokens),
            generatedTokens: try c.decode(Int.self, forKey: .generatedTokens),
            prefillSeconds: try c.decode(Double.self, forKey: .prefillSeconds),
            decodeSeconds: try c.decode(Double.self, forKey: .decodeSeconds),
            stopReason: try c.decode(StopReason.self, forKey: .stopReason),
            peakFootprintBytes: try c.decode(UInt64.self, forKey: .peakFootprintBytes),
            droppedMessages: try c.decodeIfPresent(Int.self, forKey: .droppedMessages) ?? 0
        )
        compactedTurns = try c.decodeIfPresent(Int.self, forKey: .compactedTurns) ?? 0
    }
}

public struct GenerationResult: Sendable, Hashable {
    /// Exact model output including special markers.
    public var rawOutput: String
    /// Text to store as `ChatMessage.rawModelTurn` for this answer (generation prefix + raw output).
    public var rawModelTurn: String
    public var stats: GenerationStats
    /// Set when generation stopped because the model called a tool.
    public var toolCall: ToolCall?
    /// When the model wrote the call out as plain answer text instead of tool-call tokens: that text
    /// (already streamed as answer — callers should drop it from what they show).
    public var writtenOutCall: String?

    public init(rawOutput: String, rawModelTurn: String, stats: GenerationStats, toolCall: ToolCall? = nil) {
        self.rawOutput = rawOutput
        self.rawModelTurn = rawModelTurn
        self.stats = stats
        self.toolCall = toolCall
    }
}

public enum GenerationEvent: Sendable, Equatable {
    /// Fraction of the new prompt already processed (only emitted for multi-batch prefills).
    case prefillProgress(Double)
    case chunk(OutputChunk)
    case finished(GenerationResult)
}

public enum EngineError: Error, Equatable, LocalizedError {
    case notLoaded
    case modelLoadFailed(path: String)
    case contextInitFailed
    case tokenizeFailed
    case contextOverflow(needed: Int, available: Int)
    case decodeFailed(code: Int32)
    case visionNotLoaded
    case visionLoadFailed(path: String)
    case imageDecodeFailed
    case imageEncodeFailed(code: Int32)

    public var errorDescription: String? {
        switch self {
        case .notLoaded: String(localized: "Model nie jest załadowany.", bundle: .module)
        case .modelLoadFailed: String(localized: "Nie udało się załadować modelu.", bundle: .module)
        case .contextInitFailed: String(localized: "Nie udało się utworzyć kontekstu (za mało pamięci?).", bundle: .module)
        case .tokenizeFailed: String(localized: "Nie udało się przetworzyć tekstu.", bundle: .module)
        case .contextOverflow(let needed, let available):
            String(localized: "Wiadomość jest za długa: potrzeba \(needed) tokenów, kontekst mieści \(available).", bundle: .module)
        case .decodeFailed(let code): String(localized: "Błąd inferencji (kod \(code)).", bundle: .module)
        case .visionNotLoaded: String(localized: "Moduł obrazów nie jest załadowany.", bundle: .module)
        case .visionLoadFailed: String(localized: "Nie udało się załadować modułu obrazów.", bundle: .module)
        case .imageDecodeFailed: String(localized: "Nie udało się odczytać obrazu.", bundle: .module)
        case .imageEncodeFailed(let code): String(localized: "Nie udało się przetworzyć obrazu (kod \(code)).", bundle: .module)
        }
    }
}
