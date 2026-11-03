import AVFoundation
import GemmaKit

/// Microphone input via AVAudioEngine. Deliberately *not* main-actor isolated: the tap block runs on
/// AVFAudio's realtime thread. A tap closure created inside a @MainActor type is inferred as
/// main-actor isolated, and Swift 6 traps (`dispatch_assert_queue_fail`, SIGTRAP) the moment the
/// first buffer arrives on another thread — that was the dictation crash.
/// `nonisolated` matters: this target's default isolation is MainActor.
nonisolated final class MicrophoneCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var running = false

    /// Starts capturing; `onBuffer` is called on the audio thread with each buffer and its level (0…1).
    func start(onBuffer: @escaping @Sendable (AVAudioPCMBuffer, Float) -> Void) throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP, .duckOthers])
        try audio.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw DictationError.audioUnavailable }
        input.installTap(onBus: 0, bufferSize: 2048, format: format, block: Self.tapBlock(onBuffer))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw DictationError.audioUnavailable
        }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Built in a nonisolated static context, so the block carries no actor isolation.
    private static func tapBlock(_ onBuffer: @escaping @Sendable (AVAudioPCMBuffer, Float) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in onBuffer(buffer, rms(buffer)) }
    }

    static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return min(1, (sum / Float(buffer.frameLength)).squareRoot() * 8) // scaled for display
    }
}
