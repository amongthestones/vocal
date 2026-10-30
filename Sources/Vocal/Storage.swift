import Foundation

/// Where Vocal keeps its files: ~/Library/Application Support/Vocal.
enum Storage {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Vocal", isDirectory: true)
    /// Parakeet Ultra, for English and Spanish.
    static var model: URL { modelFolder("parakeet-ultra") }

    /// Nós's Galician Whisper turbo.
    static var galicianModel: URL { modelFolder("nos-turbo-gl") }

    /// Where a model is installed in Vocal's own folder.
    static func installedModelFolder(_ name: String) -> URL {
        folder.appendingPathComponent("Models/\(name)", isDirectory: true)
    }

    /// A model installed by the scripts or the Galician download, or else the
    /// copy bundled inside a release build.
    private static func modelFolder(_ name: String) -> URL {
        let installed = installedModelFolder(name)
        if FileManager.default.fileExists(atPath: installed.path) { return installed }
        return Bundle.main.resourceURL?.appendingPathComponent("Models/\(name)", isDirectory: true) ?? installed
    }
    static let replacements = folder.appendingPathComponent("replacements.txt")
    static let history = folder.appendingPathComponent("history.txt")

    private static let replacementsHeader = """
        # Vocal replacements: one per line, what the model writes => what you want.
        # Whole words only. Capitals in the left side don't matter.
        # Edit here or in Vocal's Settings; changes apply to the next dictation.
        # Example: Coruna => Coruña


        """

    /// Makes the folder and a starter replacements file on first launch.
    static func prepare() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: replacements.path) {
            saveReplacements([])
        }
    }

    static func loadReplacements() -> [TextRules.Replacement] {
        guard let text = try? String(contentsOf: replacements, encoding: .utf8) else { return [] }
        return TextRules.parseReplacements(text)
    }

    /// Rewrites the file from the Settings table. Rows without a left side are skipped.
    static func saveReplacements(_ list: [TextRules.Replacement]) {
        let lines = list
            .filter { !$0.heard.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "\($0.heard.trimmingCharacters(in: .whitespaces)) => \($0.written.trimmingCharacters(in: .whitespaces))" }
        let text = replacementsHeader + lines.joined(separator: "\n") + "\n"
        try? text.write(to: replacements, atomically: true, encoding: .utf8)
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let log = folder.appendingPathComponent("vocal.log")

    /// State changes and errors, never the dictated text.
    static func appendToLog(_ message: String) {
        append("[\(timestamp.string(from: Date()))] \(message)\n", to: log)
    }

    /// One line per dictation: `[2026-10-30 09:12] text`.
    static func appendToHistory(_ text: String) {
        append("[\(timestamp.string(from: Date()))] \(text)\n", to: history)
    }

    private static func append(_ line: String, to file: URL) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
    }
}
