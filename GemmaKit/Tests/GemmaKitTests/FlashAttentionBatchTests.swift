import Foundation
import Testing
@testable import GemmaKit

extension RealModelTests {
    /// Regression: llama.cpp b11345 ran the non-vector flash-attention kernel on the quantized (Q8_0)
    /// KV cache for batches of 20–31 tokens and, with Gemma 4's 512-wide global heads, asked Metal for
    /// 36 864 B of threadgroup memory (limit 32 768 B). Xcode's Metal validation aborted; without it the
    /// result is undefined. Run with MTL_DEBUG_LAYER=1 to have Metal validate every dispatch.
    @Suite(.serialized)
    struct FlashAttentionBatchTests {
        @Test(arguments: ToolCallingIntegrationTests.variants)
        func everyShortBatchSizeDecodes(_ variant: ModelVariant) async throws {
            let engine = LlamaEngine()
            try await engine.load(modelURL: SmallModelTests.modelsDir.appending(path: variant.model.fileName))
            do {
                var covered = Set<Int>()
                for words in 1...40 {
                    let prompt = "<bos><|turn>user\n" + Array(repeating: "kot", count: words).joined(separator: " ") + "<turn|>\n<|turn>model\n"
                    let tokens = try await engine.countTokens(prompt)
                    guard (18...34).contains(tokens), covered.insert(tokens).inserted else { continue }
                    await engine.resetCache() // the whole prompt is one batch
                    var finished = false
                    for try await event in engine.generate(prompt: prompt, sampling: .greedy(maxTokens: 2)) {
                        if case .finished = event { finished = true }
                    }
                    #expect(finished, "\(variant.id): batch of \(tokens) tokens")
                }
                #expect(covered.isSuperset(of: 20...31), "\(variant.id): covered \(covered.sorted())")
            } catch {
                await engine.unload()
                throw error
            }
            await engine.unload()
        }
    }
}
