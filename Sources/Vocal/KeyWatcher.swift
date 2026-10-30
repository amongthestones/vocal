import AppKit

/// The keys that can start a dictation. All are modifier keys, so holding one
/// types nothing.
enum TriggerKey: String, CaseIterable {
    case fn
    case rightOption
    case rightCommand

    var title: String {
        switch self {
        case .fn: "Globe (fn)"
        case .rightOption: "Right Option"
        case .rightCommand: "Right Command"
        }
    }

    /// The SF Symbol printed on the key.
    var symbolName: String {
        switch self {
        case .fn: "globe"
        case .rightOption: "option"
        case .rightCommand: "command"
        }
    }

    /// Text that follows the key's symbol in the menu ("right" for the right-hand keys).
    var prefix: String {
        switch self {
        case .fn: ""
        case .rightOption, .rightCommand: "right "
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    /// Held together with this key, these switch dictation to Galician.
    /// Option is left out when it's the dictation key itself.
    var galicianModifiers: CGEventFlags {
        self == .rightOption ? .maskControl : [.maskControl, .maskAlternate]
    }

    /// The flag bit that is set while this exact key is down. The right-hand
    /// bits come from IOKit's NX_DEVICER*KEYMASK and tell right from left.
    var downMask: UInt64 {
        switch self {
        case .fn: CGEventFlags.maskSecondaryFn.rawValue
        case .rightOption: 0x40
        case .rightCommand: 0x10
        }
    }
}

/// Watches the keyboard through a listen-only event tap. It sees key events
/// but never changes or blocks them. Needs Input Monitoring permission.
final class KeyWatcher {
    enum Event {
        case pressed
        case released
        case otherKey
        case escape
    }

    var key: TriggerKey = .fn
    private let onEvent: (Event) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    private static let escapeKeyCode: Int64 = 53

    init(onEvent: @escaping (Event) -> Void) {
        self.onEvent = onEvent
    }

    /// Returns false when macOS hasn't granted Input Monitoring yet.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, userInfo in
                let watcher = Unmanaged<KeyWatcher>.fromOpaque(userInfo!).takeUnretainedValue()
                watcher.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Throws away the tap and makes a new one. A tap made before Input
    /// Monitoring was granted can exist but never receive a key.
    @discardableResult
    func restart() -> Bool {
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        runLoopSource = nil
        isDown = false
        return start()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS switches off a tap that it thinks is slow; turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else { return }
            let down = event.flags.rawValue & key.downMask != 0
            guard down != isDown else { return }
            isDown = down
            onEvent(down ? .pressed : .released)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == Self.escapeKeyCode {
                onEvent(.escape)
            } else if isDown {
                onEvent(.otherKey)
            }
        default:
            break
        }
    }
}
