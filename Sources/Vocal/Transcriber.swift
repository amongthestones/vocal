import FluidAudio
import Foundation
import WhisperKit

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

/// Galician: Proxecto Nós's Whisper large-v3 turbo, fine-tuned on Galician and
/// converted for the Neural Engine. Loaded from disk with downloading turned
/// off, tokenizer included, so it never reaches the network either.
actor GalicianTranscriber {
    private var kit: WhisperKit?
    private let converter = AudioConverter()

    func load(from directory: URL) async throws {
        kit = try await WhisperKit(WhisperKitConfig(
            modelFolder: directory.path,
            tokenizerFolder: directory,
            verbose: false,
            logLevel: .error,
            load: true,
            download: false))
        _ = try? await transcribe(samples: [Float](repeating: 0, count: 16_000), sampleRate: 16_000)
    }

    func unload() {
        kit = nil
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard let kit else { return "" }
        let audio = sampleRate == 16_000 ? samples : try converter.resample(samples, from: sampleRate)
        var options = DecodingOptions(language: "gl", detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: true)
        // Whisper drops a passage it's unsure of, which in dictation means
        // pasting nothing. Keep only the check that stops repetition loops.
        options.logProbThreshold = nil
        options.firstTokenLogProbThreshold = nil
        options.noSpeechThreshold = nil
        return try await kit.transcribe(audioArray: audio, decodeOptions: options)
            .map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
