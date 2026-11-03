import Foundation
import Synchronization
import llama

/// llama.cpp-backed inference engine for Gemma 4.
///
/// Runs on its own serial queue (not the cooperative pool) because decoding blocks for seconds.
/// Keeps the KV cache between calls: when a new prompt starts with the text already processed,
/// only the new suffix is prefilled — so a chat turn costs only the new user message.
/// Images go through mtmd (vision projector), loaded lazily with `loadVision`.
public actor LlamaEngine {
    private let queue = DispatchSerialQueue(label: "GemmaKit.LlamaEngine", qos: .userInitiated)
    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    private var vision: OpaquePointer?
    public private(set) var configuration: EngineConfiguration?
    /// Chat format of the loaded model, detected from its embedded template.
    public private(set) var promptFormat = PromptFormat.gemma4_12B

    /// Text whose tokens are currently in the KV cache, and how many tokens (positions) that is.
    private var processedText = ""
    private var processedTokens = 0

    /// Set from any thread to end the current generation gracefully (it still emits `.finished`).
    private let stopRequested = Atomic<Bool>(false)

    public init() {}

    /// Stops the running generation after the current token. Unlike cancelling the consuming task,
    /// the stream still delivers `.finished` with the partial output, so it can be saved.
    public nonisolated func stopGeneration() {
        stopRequested.store(true, ordering: .relaxed)
    }

    public var isLoaded: Bool { context != nil }
    public var isVisionLoaded: Bool { vision != nil }
    public var cachedTokenCount: Int { processedTokens }
    public var contextLength: Int { context.map { Int(llama_n_ctx($0)) } ?? 0 }

    // MARK: Loading

    public func load(
        modelURL: URL,
        configuration: EngineConfiguration = .init(),
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws {
        unload()
        Self.initBackend()

        var mparams = llama_model_default_params()
        mparams.n_gpu_layers = configuration.gpuLayers
        mparams.load_mode = configuration.useMmap ? LLAMA_LOAD_MODE_MMAP : LLAMA_LOAD_MODE_NONE

        let box = progress.map { ProgressBox($0) }
        if let box {
            mparams.progress_callback = { value, userData in
                Unmanaged<ProgressBox>.fromOpaque(userData!).takeUnretainedValue().report(Double(value))
                return true
            }
            mparams.progress_callback_user_data = Unmanaged.passUnretained(box).toOpaque()
        }
        let loaded = withExtendedLifetime(box) {
            llama_model_load_from_file(modelURL.path(percentEncoded: false), mparams)
        }
        guard let loaded else { throw EngineError.modelLoadFailed(path: modelURL.path) }

        var cparams = llama_context_default_params()
        cparams.n_ctx = UInt32(configuration.contextLength)
        cparams.n_batch = UInt32(configuration.batchSize)
        cparams.n_ubatch = UInt32(configuration.batchSize)
        cparams.n_seq_max = 1
        cparams.n_threads = Int32(configuration.threads)
        cparams.n_threads_batch = Int32(configuration.threads)
        cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        if configuration.quantizedKVCache {
            // A quantized V cache requires flash attention.
            cparams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_ENABLED
            cparams.type_k = GGML_TYPE_Q8_0
            cparams.type_v = GGML_TYPE_Q8_0
        }
        cparams.no_perf = true
        if configuration.gpuLayers == 0 {
            // Pure CPU: keep the KV cache and ops off the GPU too.
            cparams.offload_kqv = false
            cparams.op_offload = false
        }
        // Sliding-window layers (40 of 48) only keep the last 1024 tokens. A full-size SWA cache would
        // allow rolling back the KV cache, which we never do (we only append or clear), and costs
        // 5.4 GB instead of 0.7 GB at 16K context.
        cparams.swa_full = false

        guard let ctx = llama_init_from_model(loaded, cparams) else {
            llama_model_free(loaded)
            throw EngineError.contextInitFailed
        }
        model = loaded
        context = ctx
        vocab = llama_model_get_vocab(loaded)
        promptFormat = PromptFormat.detect(fromTemplate: llama_model_chat_template(loaded, nil).map { String(cString: $0) })
        self.configuration = configuration
    }

    /// Loads the vision projector (mmproj). Call before sending images; ~0.2 GB + encoder buffers.
    public func loadVision(mmprojURL: URL) throws {
        guard let model else { throw EngineError.notLoaded }
        guard vision == nil else { return }
        var params = mtmd_context_params_default()
        params.use_gpu = (configuration?.gpuLayers ?? -1) != 0
        params.print_timings = false
        params.n_threads = Int32(configuration?.threads ?? 4)
        params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        params.warmup = false
        if let maxTokens = configuration?.maxImageTokens { params.image_max_tokens = Int32(maxTokens) }
        guard let ctx = mtmd_init_from_file(mmprojURL.path(percentEncoded: false), model, params) else {
            throw EngineError.visionLoadFailed(path: mmprojURL.path)
        }
        vision = ctx
    }

    /// Frees the vision projector (e.g. on memory warning). Image tokens already in the KV cache stay valid.
    public func unloadVision() {
        if let vision { mtmd_free(vision) }
        vision = nil
    }

    public func unload() {
        unloadVision()
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
        context = nil
        model = nil
        vocab = nil
        configuration = nil
        processedText = ""
        processedTokens = 0
    }

    /// Drops the KV cache (e.g. when switching conversations).
    public func resetCache() {
        if let context { llama_memory_clear(llama_get_memory(context), true) }
        processedText = ""
        processedTokens = 0
    }

    // MARK: Tokenization

    public func tokenize(_ text: String) throws -> [llama_token] {
        guard let vocab else { throw EngineError.notLoaded }
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 8)
        var n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, utf8Count, &tokens, Int32(tokens.count), false, true)
        }
        guard n >= 0 else { throw EngineError.tokenizeFailed }
        return Array(tokens.prefix(Int(n)))
    }

    public func countTokens(_ text: String) throws -> Int { try tokenize(text).count }

    /// See the decode loop: a tool call at least this likely at the decision point is taken.
    static let toolCallThreshold = 0.05

    /// Id of the `<|tool_call>` control token (nil if the model has none).
    private var toolCallToken: llama_token? {
        guard let tokens = try? tokenize(GemmaPromptBuilder.Token.toolCall), tokens.count == 1 else { return nil }
        return tokens[0]
    }

    /// Softmax probability of `token` for the next position, from the last logits.
    static func probability(of token: llama_token, context: OpaquePointer, vocab: OpaquePointer) -> Double {
        guard let logits = llama_get_logits_ith(context, -1) else { return 0 }
        let n = Int(llama_vocab_n_tokens(vocab))
        var maxLogit = -Float.infinity
        for i in 0..<n { maxLogit = max(maxLogit, logits[i]) }
        var sum = 0.0
        for i in 0..<n { sum += exp(Double(logits[i] - maxLogit)) }
        return exp(Double(logits[Int(token)] - maxLogit)) / sum
    }

    // MARK: Chat

    /// Runs one chat turn: trims history to fit the context, renders the Gemma prompt and streams the answer.
    public nonisolated func chat(_ request: ChatRequest) -> AsyncThrowingStream<GenerationEvent, Error> {
        stream { engine, emit in try await engine.runChat(request, emit: emit) }
    }

    private func runChat(_ request: ChatRequest, emit: @escaping @Sendable (GenerationEvent) -> Void) throws {
        let nCtx = contextLength
        guard nCtx > 0 else { throw EngineError.notLoaded }
        let system = request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let full = (system.isEmpty ? [] : [ChatMessage.system(system)]) + request.messages

        let reserve = min(request.sampling.maxTokens, nCtx / 4)
        let format = promptFormat
        func render(_ messages: [ChatMessage]) -> String {
            GemmaPromptBuilder.render(
                messages, enableThinking: request.enableThinking, format: format,
                tools: request.tools, openModelTurn: request.continuation
            )
        }
        let window = try ContextWindow.fitCompacting(full, budget: nCtx - reserve) { messages in
            let images = messages.reduce(0) { $0 + $1.imageCount }
            return try countTokens(render(messages)) + images * ContextWindow.estimatedTokensPerImage
        }
        let fitted = window.messages
        let prompt = render(fitted)
        let images = fitted.flatMap(\.images)
        // Text of the model turn before this generation: a fresh generation prefix, or the turn being continued.
        let turnSoFar = request.continuation
            ?? GemmaPromptBuilder.generationPrefix(enableThinking: request.enableThinking, format: promptFormat)

        try run(prompt: prompt, images: images, sampling: request.sampling, toolNames: Set(request.tools.map(\.name)), forceToolCall: request.forceToolCall) { event in
            if case .finished(var result) = event {
                result.rawModelTurn = turnSoFar + result.rawOutput
                result.stats.droppedMessages = full.count - fitted.count
                result.stats.compactedTurns = window.compactedTurns
                emit(.finished(result))
            } else {
                emit(event)
            }
        }
    }

    // MARK: Generation

    /// Streams the model's continuation of `prompt` (a fully rendered Gemma prompt).
    /// `images` are all images referenced by `<|image|>` placeholders in the prompt, in order.
    /// Cancelling the consuming task stops generation after the current token.
    public nonisolated func generate(
        prompt: String,
        images: [Data] = [],
        sampling: SamplingParameters = .init()
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        stream { engine, emit in try await engine.run(prompt: prompt, images: images, sampling: sampling, emit: emit) }
    }

    private nonisolated func stream(
        _ body: @escaping @Sendable (LlamaEngine, @escaping @Sendable (GenerationEvent) -> Void) async throws -> Void
    ) -> AsyncThrowingStream<GenerationEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await body(self) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        prompt: String,
        images: [Data],
        sampling: SamplingParameters,
        toolNames: Set<String> = [],
        forceToolCall: Bool = false,
        emit: @escaping @Sendable (GenerationEvent) -> Void
    ) throws {
        guard let context, let vocab else { throw EngineError.notLoaded }
        stopRequested.store(false, ordering: .relaxed)
        let nCtx = Int(llama_n_ctx(context))
        var peakFootprint = DeviceDiagnostics.physicalFootprint()

        // 1. Reuse the KV cache when the prompt extends what we already processed.
        let suffix: String
        if !processedText.isEmpty, prompt.utf8.starts(with: processedText.utf8) {
            suffix = String(decoding: prompt.utf8.dropFirst(processedText.utf8.count), as: UTF8.self)
        } else {
            resetCache()
            suffix = prompt
        }
        let reused = processedTokens
        let batchSize = configuration?.batchSize ?? 512

        // 2. Prefill the new part (text only, or text + images through mtmd).
        let clock = ContinuousClock()
        let prefillStart = clock.now
        let newTokens: Int
        do {
            let imagesInSuffix = suffix.components(separatedBy: GemmaPromptBuilder.Token.image).count - 1
            if imagesInSuffix > 0 {
                newTokens = try prefillMultimodal(suffix, images: Array(images.suffix(imagesInSuffix)), context: context, nCtx: nCtx)
            } else {
                let tokens = try tokenize(suffix)
                try ensureFits(tokens.count, nCtx: nCtx)
                try decode(tokens, context: context) { done in
                    if tokens.count > batchSize { emit(.prefillProgress(Double(done) / Double(tokens.count))) }
                }
                newTokens = tokens.count
            }
            llama_synchronize(context) // Metal runs asynchronously; wait so the timing is real
        } catch is CancellationError {
            // Stopped during prefill (e.g. app went to background): nothing generated, cache dropped.
            resetCache()
            let stats = GenerationStats(promptTokens: 0, reusedTokens: reused, generatedTokens: 0, prefillSeconds: 0,
                                        decodeSeconds: 0, stopReason: .cancelled, peakFootprintBytes: peakFootprint)
            emit(.finished(GenerationResult(rawOutput: "", rawModelTurn: "", stats: stats)))
            return
        } catch {
            recover(from: error)
            throw error
        }
        processedText += suffix
        processedTokens += newTokens
        let prefillDuration = clock.now - prefillStart
        peakFootprint = max(peakFootprint, DeviceDiagnostics.physicalFootprint())

        // 3. Decode loop.
        let sampler = makeSampler(sampling)
        defer { llama_sampler_free(sampler) }
        // With tools, the first answer token decides "call a tool or write" — sampled at the user's
        // temperature the small models often skip the call, fake it as plain text or claim "saved!"
        // without saving (measured at T=1: E4B saved 14/20, E2B read memory 2/20; greedy: every time).
        // So that decision (at the start and right after thinking) and the call itself are greedy;
        // the rest of the answer keeps the user's sampling.
        // Styles and small models can still leave the call as the runner-up (E2B, "concise" style:
        // p = 0.03–0.10, while questions that need no tool stay ≤ 0.002), so a call that is at least
        // `toolCallThreshold` likely is taken even when it is not the top token.
        let greedyToolDecisions = !toolNames.isEmpty
        let toolCallID = greedyToolDecisions ? toolCallToken : nil
        let greedy = llama_sampler_init_greedy()!
        defer { llama_sampler_free(greedy) }
        var decisionPending = greedyToolDecisions
        var insideToolCall = false

        var parser = ModelOutputParser(startInThinking: prompt.hasSuffix(GemmaPromptBuilder.Token.channelStart + "thought\n"))
        var toolCall: ToolCall?
        var utf8 = UTF8Accumulator()
        var raw = ""
        var answerText = ""
        var generated = 0
        var stopReason = GenerationStats.StopReason.maxTokens
        let decodeStart = clock.now
        var pieceBuffer = [CChar](repeating: 0, count: 256)
        func append(_ text: String, kind: ModelOutputParser.TokenKind) {
            guard !text.isEmpty else { return }
            raw += text
            processedText += text
            guard let chunk = parser.consume(text, kind: kind) else { return }
            if case .toolCall(let call) = chunk { toolCall = call }
            if case .answer(let text) = chunk { answerText += text }
            emit(.chunk(chunk))
        }

        while generated < sampling.maxTokens {
            if Task.isCancelled || stopRequested.load(ordering: .relaxed) { stopReason = .cancelled; break }
            if processedTokens >= nCtx { stopReason = .contextFull; break }

            var forced: llama_token?
            if decisionPending, let id = toolCallID {
                let p = Self.probability(of: id, context: context, vocab: vocab)
                if getenv("GEMMA_TOOL_DEBUG") != nil { print("TOOLDECISION p=\(String(format: "%.4f", p))") }
                if p >= Self.toolCallThreshold || (forceToolCall && generated == 0) { forced = id }
            }
            let token = forced ?? llama_sampler_sample(decisionPending || insideToolCall ? greedy : sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { stopReason = toolCall == nil ? .endOfTurn : .toolCall; break }

            let kind = Self.tokenKind(token, vocab: vocab)
            let bytes = Self.piece(token, vocab: vocab, buffer: &pieceBuffer)
            if greedyToolDecisions {
                let special = kind == .text ? nil : String(decoding: bytes, as: UTF8.self)
                switch special {
                case GemmaPromptBuilder.Token.toolCall: insideToolCall = true; decisionPending = false
                case GemmaPromptBuilder.Token.toolCallEnd: insideToolCall = false
                case GemmaPromptBuilder.Token.channelEnd: decisionPending = true // thinking done → decide now
                case GemmaPromptBuilder.Token.channelStart: decisionPending = false
                default: if !insideToolCall { decisionPending = false }
                }
            }
            // After a call the model hands over with <|tool_response>: stop here, without decoding it —
            // the caller continues the turn with the real response block.
            if kind != .text, String(decoding: bytes, as: UTF8.self) == GemmaPromptBuilder.Token.toolResponse {
                stopReason = .toolCall
                break
            }

            do {
                try decode([token], context: context)
            } catch {
                recover(from: error)
                throw error
            }
            generated += 1
            processedTokens += 1

            if kind == .text {
                append(utf8.append(bytes), kind: .text)
            } else {
                append(utf8.flush(), kind: .text)
                append(String(decoding: bytes, as: UTF8.self), kind: kind)
            }

            if generated % 16 == 0 { peakFootprint = max(peakFootprint, DeviceDiagnostics.physicalFootprint()) }
        }
        append(utf8.flush(), kind: .text)

        // The model wrote the call out as text (`memory_save(name='…')`) instead of using the tokens.
        var writtenOutCall: String?
        if toolCall == nil, stopReason == .endOfTurn, let call = ToolCall.parseWrittenOut(answerText, toolNames: toolNames) {
            toolCall = call
            stopReason = .toolCall
            writtenOutCall = answerText
        }

        let stats = GenerationStats(
            promptTokens: newTokens,
            reusedTokens: reused,
            generatedTokens: generated,
            prefillSeconds: prefillDuration.seconds,
            decodeSeconds: (clock.now - decodeStart).seconds,
            stopReason: stopReason,
            peakFootprintBytes: max(peakFootprint, DeviceDiagnostics.physicalFootprint())
        )
        var result = GenerationResult(rawOutput: raw, rawModelTurn: raw, stats: stats, toolCall: toolCall)
        result.writtenOutCall = writtenOutCall
        emit(.finished(result))
    }

    /// After a failed `llama_decode` the KV cache no longer matches `processedText`. A negative code means
    /// the GPU command buffer failed (e.g. out of GPU memory) — ggml-metal then stays in an error state
    /// until the backend is recreated, so drop the model; the next request reloads it.
    private func recover(from error: Error) {
        switch error as? EngineError {
        case .decodeFailed(let code) where code < 0, .imageEncodeFailed(let code) where code < 0:
            unload()
        default:
            resetCache()
        }
    }

    private func ensureFits(_ newTokens: Int, nCtx: Int) throws {
        let needed = processedTokens + newTokens + 1
        guard needed <= nCtx else { throw EngineError.contextOverflow(needed: needed, available: nCtx) }
    }

    /// Prefills text containing `<|image|>` placeholders. Returns the number of positions added.
    private func prefillMultimodal(_ text: String, images: [Data], context: OpaquePointer, nCtx: Int) throws -> Int {
        guard let vision else { throw EngineError.visionNotLoaded }
        let marker = String(cString: mtmd_default_marker())
        let mtmdText = text.replacingOccurrences(of: GemmaPromptBuilder.Token.image, with: marker)

        var bitmaps: [OpaquePointer?] = []
        defer { bitmaps.forEach { mtmd_bitmap_free($0) } }
        for data in images {
            guard let rgb = ImageDecoder.rgb(from: data),
                  let bitmap = rgb.pixels.withUnsafeBufferPointer({
                      mtmd_bitmap_init(UInt32(rgb.width), UInt32(rgb.height), $0.baseAddress)
                  })
            else { throw EngineError.imageDecodeFailed }
            bitmaps.append(bitmap)
        }

        guard let chunks = mtmd_input_chunks_init() else { throw EngineError.tokenizeFailed }
        defer { mtmd_input_chunks_free(chunks) }

        let tokenizeResult = mtmdText.withCString { cText in
            var input = mtmd_input_text(text: cText, text_len: strlen(cText), add_special: false, parse_special: true)
            return bitmaps.withUnsafeBufferPointer {
                mtmd_tokenize(vision, chunks, &input, $0.baseAddress, $0.count)
            }
        }
        guard tokenizeResult == 0 else { throw EngineError.imageEncodeFailed(code: tokenizeResult) }

        let positions = Int(mtmd_helper_get_n_pos(chunks))
        try ensureFits(positions, nCtx: nCtx)

        var newPast: llama_pos = 0
        let code = mtmd_helper_eval_chunks(
            vision, context, chunks, llama_pos(processedTokens), 0,
            Int32(configuration?.batchSize ?? 512), true, &newPast
        )
        guard code == 0 else { throw EngineError.imageEncodeFailed(code: code) }
        return Int(newPast) - processedTokens
    }

    private func decode(_ tokens: [llama_token], context: OpaquePointer, progress: ((Int) -> Void)? = nil) throws {
        guard !tokens.isEmpty else { return }
        let batchSize = configuration?.batchSize ?? 512
        var tokens = tokens
        var offset = 0
        while offset < tokens.count {
            let count = min(batchSize, tokens.count - offset)
            let code = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress! + offset, Int32(count)))
            }
            guard code == 0 else { throw EngineError.decodeFailed(code: code) }
            offset += count
            if offset < tokens.count, Task.isCancelled || stopRequested.load(ordering: .relaxed) {
                throw CancellationError()
            }
            if let progress {
                llama_synchronize(context)
                progress(offset)
            }
        }
    }

    private func makeSampler(_ p: SamplingParameters) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        if p.temperature <= 0 {
            llama_sampler_chain_add(chain, llama_sampler_init_greedy())
        } else {
            if p.topK > 0 { llama_sampler_chain_add(chain, llama_sampler_init_top_k(p.topK)) }
            if p.topP < 1 { llama_sampler_chain_add(chain, llama_sampler_init_top_p(p.topP, 1)) }
            if p.minP > 0 { llama_sampler_chain_add(chain, llama_sampler_init_min_p(p.minP, 1)) }
            llama_sampler_chain_add(chain, llama_sampler_init_temp(p.temperature))
            llama_sampler_chain_add(chain, llama_sampler_init_dist(p.seed))
        }
        return chain
    }

    private static func tokenKind(_ token: llama_token, vocab: OpaquePointer) -> ModelOutputParser.TokenKind {
        let attr = llama_vocab_get_attr(vocab, token).rawValue
        if attr & LLAMA_TOKEN_ATTR_CONTROL.rawValue != 0 { return .control }
        if attr & LLAMA_TOKEN_ATTR_USER_DEFINED.rawValue != 0 { return .userDefined }
        return .text
    }

    private static func piece(_ token: llama_token, vocab: OpaquePointer, buffer: inout [CChar]) -> [UInt8] {
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        return buffer.prefix(Int(max(n, 0))).map { UInt8(bitPattern: $0) }
    }

    private static let backendInit: Void = {
        #if os(iOS)
        // By default ggml-metal keeps every model buffer in a residency set and re-requests residency
        // every 5 ms until 3 minutes after the last computation — the weights stay *wired* (not
        // reclaimable, not counted in the app's footprint) even after the model is freed. Measured on an
        // iPhone 17 Pro Max with 12B: system wired 1.8 → 9.4 GB for as long as the app runs, free RAM
        // ~70 MB → jetsam storms, display glitches, APFS stalls and a watchdog panic.
        // Without residency sets memory is wired only while the GPU computes (back to 1.7 GB when idle);
        // decode speed is unchanged, prefill ~10% slower. Must be set before the Metal device is created.
        setenv("GGML_METAL_NO_RESIDENCY", "1", 0)
        #endif
        let logger: ggml_log_callback = { level, text, _ in
            #if DEBUG
            let verbose = getenv("GEMMA_VERBOSE") != nil
            if verbose || level.rawValue >= GGML_LOG_LEVEL_WARN.rawValue, let text { fputs(String(cString: text), stderr) }
            #endif
        }
        llama_log_set(logger, nil)
        mtmd_helper_log_set(logger, nil)
        llama_backend_init()
    }()

    private static func initBackend() { _ = backendInit }
}

private final class ProgressBox: @unchecked Sendable {
    let handler: @Sendable (Double) -> Void
    init(_ handler: @escaping @Sendable (Double) -> Void) { self.handler = handler }
    func report(_ value: Double) { handler(value) }
}

extension Duration {
    var seconds: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
