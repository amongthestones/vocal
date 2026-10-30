import AVFoundation
import AppKit
import Observation

/// Ties the key, microphone, model and paste together.
@MainActor
@Observable
final class Dictation {
    enum State: Equatable {
        case loading
        case ready
        case listening(handsFree: Bool, galician: Bool)
        case transcribing
        case problem(Problem)
    }

    enum Problem: Hashable {
        case microphone
        case inputMonitoring
        case accessibility
        /// Both keyboard permissions are on, but macOS only applies them after a relaunch.
        case needsRestart
        case noModel
        case modelFailed(String)
        case microphoneFailed

        var message: String {
            switch self {
            case .microphone: "Needs microphone access"
            case .inputMonitoring: "Needs Input Monitoring"
            case .accessibility: "Needs Accessibility"
            case .needsRestart: "Restart Vocal to finish setup"
            case .noModel: "Model not found"
            case .modelFailed(let reason): "Model didn't load: \(reason)"
            case .microphoneFailed: "Microphone didn't start"
            }
        }
    }

    private(set) var state: State = .loading {
        didSet {
            guard state != oldValue else { return }
            Storage.appendToLog("\(state)")
            onChange()
        }
    }
    private(set) var lastText: String?
    /// Whether the Galician model is loaded; Galician dictation needs it.
    private(set) var galicianReady = false
    private(set) var galicianLoading = false

    var key: TriggerKey {
        didSet {
            keyWatcher?.key = key
            UserDefaults.standard.set(key.rawValue, forKey: "key")
            onChange()
        }
    }
    var removeFillers: Bool {
        didSet { UserDefaults.standard.set(removeFillers, forKey: "removeFillers") }
    }

    @ObservationIgnored var onChange: () -> Void = {}

    @ObservationIgnored private let recorder = Recorder()
    @ObservationIgnored private let transcriber = Transcriber()
    @ObservationIgnored private let galician = GalicianTranscriber()
    /// The language of the recording in progress, chosen when it starts.
    @ObservationIgnored private var recordingGalician = false
    @ObservationIgnored private var keyWatcher: KeyWatcher?
    @ObservationIgnored private var logic = PressLogic()
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var asked: Set<Problem> = []

    init() {
        key = UserDefaults.standard.string(forKey: "key").flatMap(TriggerKey.init) ?? .fn
        removeFillers = UserDefaults.standard.bool(forKey: "removeFillers")
    }

    func start() {
        Storage.prepare()
        // Try Again calls this again; keep one watcher, since its event tap
        // holds an unretained pointer to it.
        let watcher = keyWatcher ?? KeyWatcher { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        watcher.key = key
        keyWatcher = watcher

        Task {
            Storage.appendToLog("starting: microphone \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue), input monitoring \(Permissions.hasInputMonitoring), accessibility \(Permissions.hasAccessibility)")
            guard await Permissions.requestMicrophone() else {
                state = .problem(.microphone)
                return
            }
            if keyboardReady() {
                await loadModel()
            } else {
                waitForKeyboardPermissions()
            }
        }
    }

    /// Tries again after a problem, from the menu.
    func retry() {
        guard case .problem = state else { return }
        state = .loading
        start()
    }

    /// Asks for one keyboard permission at a time (two system prompts at once
    /// stack up confusingly) and starts the key watcher once both are on.
    private func keyboardReady() -> Bool {
        // The preflight check only updates after a relaunch, but the event tap
        // itself starts as soon as the switch is on, so try that too.
        if !Permissions.hasInputMonitoring && keyWatcher?.start() != true {
            if asked.insert(.inputMonitoring).inserted { _ = CGRequestListenEventAccess() }
            state = .problem(.inputMonitoring)
            return false
        }
        if !Permissions.hasAccessibility {
            if asked.insert(.accessibility).inserted { _ = CGRequestPostEventAccess() }
            state = .problem(.accessibility)
            return false
        }
        guard keyWatcher?.start() == true else {
            state = .problem(.needsRestart)
            return false
        }
        return true
    }

    /// Checks every second while System Settings is open, so granting a
    /// permission is enough; no need to come back and press anything.
    private func waitForKeyboardPermissions() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, self.state != .problem(.needsRestart) else {
                    timer.invalidate()
                    return
                }
                guard self.keyboardReady() else { return }
                timer.invalidate()
                self.permissionTimer = nil
                // The permissions arrived while Vocal was running; a tap made
                // earlier may be deaf, so make a fresh one.
                self.keyWatcher?.restart()
                self.state = .loading
                Task { await self.loadModel() }
            }
        }
    }

    private func loadModel() async {
        guard FileManager.default.fileExists(atPath: Storage.model.path) else {
            state = .problem(.noModel)
            return
        }
        do {
            try await transcriber.load(from: Storage.model)
            state = .ready
        } catch {
            state = .problem(.modelFailed(error.localizedDescription))
            return
        }
        await loadGalician()
    }

    /// Galician is optional: without its model, the modifier is ignored.
    func loadGalician() async {
        guard !galicianReady, !galicianLoading,
              FileManager.default.fileExists(atPath: Storage.galicianModel.path) else { return }
        galicianLoading = true
        defer { galicianLoading = false }
        do {
            try await galician.load(from: Storage.galicianModel)
            galicianReady = true
            Storage.appendToLog("galician model ready")
        } catch {
            Storage.appendToLog("galician model didn't load: \(error)")
        }
    }

    /// Unloads the Galician model and deletes the downloaded copy.
    func removeGalician() async {
        galicianReady = false
        await galician.unload()
        try? FileManager.default.removeItem(at: Storage.installedModelFolder("nos-turbo-gl"))
        Storage.appendToLog("galician model removed")
    }

    private func handle(_ event: KeyWatcher.Event) {
        let now = ProcessInfo.processInfo.systemUptime
        let action: PressAction
        switch event {
        case .pressed:
            action = logic.press(at: now)
            if case .pending = logic.mode {
                DispatchQueue.main.asyncAfter(deadline: .now() + logic.beat) { [weak self] in
                    guard let self else { return }
                    perform(logic.beatPassed(at: ProcessInfo.processInfo.systemUptime))
                }
            }
        case .released: action = logic.release(at: now)
        case .otherKey: action = logic.otherKey()
        case .escape: action = logic.escape()
        }
        perform(action)
    }

    private func perform(_ action: PressAction) {
        switch action {
        case .none:
            break
        case .start:
            // Only start from ready; a press while transcribing is ignored.
            guard state == .ready else {
                logic = PressLogic()
                return
            }
            if !recorder.isRecording {
                do {
                    try recorder.start()
                } catch {
                    logic = PressLogic()
                    state = .problem(.microphoneFailed)
                    return
                }
            }
            // Option or Control held with the key means Galician. Checked now,
            // a beat after the press, so the modifier can come slightly late.
            let flags = CGEventSource.flagsState(.combinedSessionState)
            recordingGalician = galicianReady && !flags.intersection(key.galicianModifiers).isEmpty
            state = .listening(handsFree: logic.mode == .handsFree, galician: recordingGalician)
        case .cancel:
            _ = recorder.stop()
            if case .listening = state { state = .ready }
        case .stopAndTranscribe:
            let samples = recorder.stop()
            let sampleRate = recorder.sampleRate
            guard !samples.isEmpty else {
                state = .ready
                return
            }
            state = .transcribing
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            Storage.appendToLog(String(format: "recorded %.1f s at %.0f Hz, peak %.3f", Double(samples.count) / sampleRate, sampleRate, peak))
            Task {
                let raw: String
                do {
                    raw = recordingGalician
                        ? try await galician.transcribe(samples: samples, sampleRate: sampleRate)
                        : try await transcriber.transcribe(samples: samples, sampleRate: sampleRate)
                    Storage.appendToLog("transcript: \(raw.count) characters")
                } catch {
                    raw = ""
                    Storage.appendToLog("transcription failed: \(error)")
                }
                let rules = TextRules(replacements: Storage.loadReplacements(), removeFillers: removeFillers)
                let text = rules.apply(to: raw)
                if !text.isEmpty {
                    lastText = text
                    Paster.paste(text)
                    Storage.appendToHistory(text)
                }
                state = .ready
            }
        }
    }
}

enum Permissions {
    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Input Monitoring lets Vocal see the key.
    static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    /// Accessibility lets Vocal press ⌘V. `AXIsProcessTrusted` updates as soon
    /// as the switch is turned on, without a relaunch.
    static var hasAccessibility: Bool { AXIsProcessTrusted() || CGPreflightPostEventAccess() }

    /// Opens System Settings at the pane for a problem.
    static func openSettings(for problem: Dictation.Problem) {
        let pane: String
        switch problem {
        case .microphone, .microphoneFailed: pane = "Privacy_Microphone"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .accessibility: pane = "Privacy_Accessibility"
        default: pane = "Privacy"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }

    /// Quits and opens a fresh copy, which macOS needs before it applies Input Monitoring.
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
