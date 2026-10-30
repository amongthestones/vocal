import CryptoKit
import Foundation
import Observation

/// Where the optional Galician model comes from: a release of Vocal's own
/// GitHub repo, checked against a fingerprint built into the app.
enum GalicianModel {
    static let url = URL(string: "https://github.com/amongthestones/vocal/releases/download/galician-model-1/galician-model-1.zip")!
    static let sha256 = "6f16efa84811d39a44f3ccc7aeae397e4432aafefaf770ad20f8b2d907fcb31e"
    static let sizeText = "1.5 GB"

    /// Unzips a checked download into Vocal's model folder. Returns an error message, or nil.
    static func install(zip: URL) -> String? {
        defer { try? FileManager.default.removeItem(at: zip) }
        guard let hash = sha256(of: zip), hash == sha256 else {
            return "The download didn't match its fingerprint, so it wasn't installed."
        }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("vocal-galician-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            return "Couldn't unzip the model."
        }
        let unzipped = work.appendingPathComponent("nos-turbo-gl")
        guard ditto.terminationStatus == 0, FileManager.default.fileExists(atPath: unzipped.path) else {
            return "Couldn't unzip the model."
        }
        let destination = Storage.installedModelFolder("nos-turbo-gl")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: unzipped, to: destination)
        } catch {
            return "Couldn't install the model: \(error.localizedDescription)"
        }
        return nil
    }

    /// Hashes the file in pieces, so 1.5 GB never sits in memory at once.
    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Downloads the Galician model when the person asks for it in Settings.
/// This is the only time Vocal uses the network.
@MainActor
@Observable
final class GalicianDownload {
    enum Phase: Equatable {
        case idle
        case downloading(Double)
        case installing
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    @ObservationIgnored var onInstalled: () -> Void = {}
    @ObservationIgnored private var task: URLSessionDownloadTask?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?

    func start() {
        guard task == nil else { return }
        phase = .downloading(0)
        Storage.appendToLog("galician model: download started")
        let task = URLSession.shared.downloadTask(with: GalicianModel.url) { [weak self] location, response, error in
            // The system deletes `location` when this returns, so move it first.
            var kept: URL?
            if let location, (response as? HTTPURLResponse)?.statusCode == 200 {
                let copy = FileManager.default.temporaryDirectory.appendingPathComponent("galician-model-\(UUID().uuidString).zip")
                if (try? FileManager.default.moveItem(at: location, to: copy)) != nil { kept = copy }
            }
            Task { @MainActor in self?.finish(file: kept, error: error) }
        }
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in
                guard let self, case .downloading = self.phase else { return }
                self.phase = .downloading(fraction)
            }
        }
        self.task = task
        task.resume()
    }

    func cancel() {
        task?.cancel()
    }

    private func finish(file: URL?, error: Error?) {
        task = nil
        progressObservation = nil
        if let error {
            phase = (error as? URLError)?.code == .cancelled ? .idle : .failed("The download failed: \(error.localizedDescription)")
            Storage.appendToLog("galician model: download ended: \(error)")
            return
        }
        guard let file else {
            phase = .failed("The download failed. Check your connection and try again.")
            return
        }
        phase = .installing
        Task.detached {
            let problem = GalicianModel.install(zip: file)
            await MainActor.run {
                if let problem {
                    self.phase = .failed(problem)
                    Storage.appendToLog("galician model: \(problem)")
                } else {
                    self.phase = .idle
                    Storage.appendToLog("galician model: installed")
                    self.onInstalled()
                }
            }
        }
    }
}
