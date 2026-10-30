import Foundation

/// What the app should do after a trigger key event.
enum PressAction: Equatable {
    case none
    case start
    case stopAndTranscribe
    case cancel
}

/// Turns presses and releases of the trigger key into recording actions.
///
/// - Hold the key: after a beat, recording starts. Release to transcribe.
/// - A quick tap does nothing, so the key keeps its macOS job (🌐 switching
///   the keyboard, say) and brushing it never records.
/// - Tap, then press again quickly: hands-free. The next press stops.
/// - Another key while holding means it was a shortcut (Fn+Delete, say): cancel.
/// - Escape cancels any recording.
struct PressLogic {
    enum Mode: Equatable {
        case idle
        case pending(since: TimeInterval)
        case holding
        case handsFree
    }

    /// How long the key has to be held before recording starts.
    var beat: TimeInterval = 0.25
    /// The longest gap between a tap and the press that turns on hands-free.
    var doublePressWindow: TimeInterval = 0.3

    private(set) var mode: Mode = .idle
    private var lastTapEnd: TimeInterval?

    mutating func press(at time: TimeInterval) -> PressAction {
        switch mode {
        case .handsFree:
            mode = .idle
            return .stopAndTranscribe
        case .idle:
            if let lastTapEnd, time - lastTapEnd < doublePressWindow {
                self.lastTapEnd = nil
                mode = .handsFree
                return .start
            }
            mode = .pending(since: time)
            return .none
        case .pending, .holding:
            return .none
        }
    }

    /// Called once the beat has passed since a press. Starts recording if
    /// that same press is still held.
    mutating func beatPassed(at time: TimeInterval) -> PressAction {
        guard case .pending(let since) = mode, time - since >= beat * 0.99 else { return .none }
        mode = .holding
        return .start
    }

    mutating func release(at time: TimeInterval) -> PressAction {
        switch mode {
        case .pending:
            mode = .idle
            lastTapEnd = time
            return .none
        case .holding:
            mode = .idle
            return .stopAndTranscribe
        case .idle, .handsFree:
            return .none
        }
    }

    mutating func otherKey() -> PressAction {
        switch mode {
        case .pending:
            mode = .idle
            lastTapEnd = nil
            return .none
        case .holding:
            mode = .idle
            lastTapEnd = nil
            return .cancel
        case .idle, .handsFree:
            return .none
        }
    }

    mutating func escape() -> PressAction {
        lastTapEnd = nil
        switch mode {
        case .idle:
            return .none
        case .pending:
            mode = .idle
            return .none
        case .holding, .handsFree:
            mode = .idle
            return .cancel
        }
    }
}
