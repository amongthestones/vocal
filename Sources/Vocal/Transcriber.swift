import FluidAudio
import Foundation

/// Parakeet Ultra, loaded from Vocal's own folder. `loadLocal` reads the files
/// on disk and never downloads, so a missing model is an error, not a fetch.
actor Transcriber {
    private let manager = AsrManager(config: .default)
    private let converter = AudioConverter()

    func load(from directory: URL) async throws {
        let models = try AsrModels.loadLocal(from: directory, version: .ultra)
        try await manager.loadModels(models)
        // The first run after loading is slow while Core ML settles; do it now,
        // on a second of silence, instead of on your first dictation.
        _ = try? await transcribe(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        var audio = sampleRate == 16_000 ? samples : try converter.resample(samples, from: sampleRate)
        // Parakeet wants at least a second of audio.
        if audio.count < 16_000 {
            audio += [Float](repeating: 0, count: 16_000 - audio.count)
        }
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(audio, decoderState: &state)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
