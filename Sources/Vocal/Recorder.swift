import AVFoundation

/// Records the default microphone into memory. The engine only runs while
/// recording, so the orange mic dot only shows while you talk.
final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private(set) var sampleRate: Double = 48_000
    private(set) var isRecording = false

    func start() throws {
        guard !isRecording else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true) }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        sampleRate = format.sampleRate
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let channels = buffer.floatChannelData else { return }
            // First channel only: dictation is one voice.
            let chunk = UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength))
            self.lock.withLock { self.samples.append(contentsOf: chunk) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    /// Stops and returns everything recorded since `start()`.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        return lock.withLock { samples }
    }
}
