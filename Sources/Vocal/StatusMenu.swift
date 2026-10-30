import AppKit

/// The menu bar item. The icon shows the state at a glance; settings live in
/// the Settings window.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let dictation: Dictation
    private let settings: SettingsWindowController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(dictation: Dictation) {
        self.dictation = dictation
        settings = SettingsWindowController(dictation: dictation)
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        dictation.onChange = { [weak self] in self?.updateIcon() }
        updateIcon()
    }

    private func updateIcon() {
        let symbol: String
        switch dictation.state {
        case .loading: symbol = "waveform.badge.ellipsis"
        case .ready: symbol = "waveform"
        // Not a mic: macOS already shows its own mic indicator while recording.
        case .listening: symbol = "waveform.circle.fill"
        case .transcribing: symbol = "ellipsis"
        case .problem: symbol = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Vocal")
            ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Vocal")
        image?.isTemplate = true
        item.button?.image = image
    }

    /// The first line of the menu, with the key drawn as its SF Symbol.
    private var statusLine: NSAttributedString {
        let key = dictation.key
        func withKey(_ before: String, _ after: String) -> NSAttributedString {
            let text = NSMutableAttributedString(string: before + key.prefix)
            if let image = NSImage(systemSymbolName: key.symbolName, accessibilityDescription: key.title) {
                let attachment = NSTextAttachment()
                attachment.image = image
                text.append(NSAttributedString(attachment: attachment))
            }
            text.append(NSAttributedString(string: after))
            text.addAttributes([.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor],
                               range: NSRange(location: 0, length: text.length))
            return text
        }
        switch dictation.state {
        case .loading: return withKey("Loading…", "")
        case .ready: return withKey("Hold ", " to talk")
        case .listening(let handsFree): return handsFree ? withKey("Press ", " to stop") : withKey("Listening…", "")
        case .transcribing: return withKey("Writing…", "")
        case .problem(let problem): return withKey(problem.message, "")
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.attributedTitle = statusLine
        status.isEnabled = false
        menu.addItem(status)

        if case .problem(let problem) = dictation.state {
            switch problem {
            case .microphone:
                menu.addItem(action("Open Microphone Settings…", #selector(openPrivacy)))
            case .inputMonitoring:
                menu.addItem(action("Open Input Monitoring Settings…", #selector(openPrivacy)))
            case .accessibility:
                menu.addItem(action("Open Accessibility Settings…", #selector(openPrivacy)))
            case .needsRestart:
                menu.addItem(action("Restart Vocal", #selector(restart)))
            case .noModel:
                menu.addItem(disabled("Run scripts/install-model.sh, then try again"))
                menu.addItem(action("Try Again", #selector(retry)))
            case .modelFailed, .microphoneFailed:
                menu.addItem(action("Try Again", #selector(retry)))
            }
        }

        menu.addItem(.separator())
        if dictation.lastText != nil {
            menu.addItem(action("Copy Last Dictation", #selector(copyLast)))
        }
        menu.addItem(action("Open History", #selector(openHistory)))
        menu.addItem(action("Settings…", #selector(showSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Vocal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        return entry
    }

    @objc private func showSettings() {
        settings.show()
    }

    /// Opens the menu without a click, for screenshots.
    func openMenu() {
        item.button?.performClick(nil)
    }

    func openSettings(tab index: Int) {
        settings.show(tab: index)
    }

    @objc private func openHistory() {
        if !FileManager.default.fileExists(atPath: Storage.history.path) {
            try? Data().write(to: Storage.history)
        }
        NSWorkspace.shared.open(Storage.history)
    }

    @objc private func copyLast() {
        if let last = dictation.lastText { Paster.copy(last) }
    }

    @objc private func openPrivacy() {
        if case .problem(let problem) = dictation.state { Permissions.openSettings(for: problem) }
    }

    @objc private func restart() {
        Permissions.relaunch()
    }

    @objc private func retry() {
        dictation.retry()
    }
}
