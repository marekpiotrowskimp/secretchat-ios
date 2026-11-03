import Foundation

/// Keeps a conversation inside the model's context window by dropping the oldest turns.
public enum ContextWindow {
    /// Rough per-image token cost used for budgeting (Gemma 4 vision encodes an image into ~256–280 tokens).
    public static let estimatedTokensPerImage = 300

    /// Returns the messages that fit `budget` tokens.
    ///
    /// A leading system message and the last message are always kept. When trimming is needed, it
    /// cuts down to `targetRatio` of the budget so the next few turns don't trigger another trim —
    /// each trim invalidates the KV cache and forces a full prefill.
    public static func fit(
        _ messages: [ChatMessage],
        budget: Int,
        targetRatio: Double = 0.7,
        cost: ([ChatMessage]) throws -> Int
    ) rethrows -> [ChatMessage] {
        guard try cost(messages) > budget else { return messages }

        let system = messages.first?.role == .system ? messages.first : nil
        var rest = Array(messages.dropFirst(system == nil ? 0 : 1))
        let target = Int(Double(budget) * targetRatio)

        func assembled() -> [ChatMessage] { (system.map { [$0] } ?? []) + rest }

        while rest.count > 1 {
            rest.removeFirst()
            // A conversation must start with a user turn.
            while rest.count > 1, rest.first?.role != .user { rest.removeFirst() }
            if try cost(assembled()) <= target { break }
        }
        return assembled()
    }
}
