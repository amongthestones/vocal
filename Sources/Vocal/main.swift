import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let dictation = Dictation()
    private var statusMenu: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusMenu = StatusMenuController(dictation: dictation)
        dictation.start()
        // `open Vocal.app --args --settings 1` opens straight to a Settings tab, for checking the window.
        if let flag = CommandLine.arguments.firstIndex(of: "--settings") {
            let next = CommandLine.arguments.dropFirst(flag + 1).first
            statusMenu?.openSettings(tab: next.flatMap(Int.init) ?? 0)
        }
        // `--menu` opens the menu bar menu once the model is loaded, for screenshots.
        if CommandLine.arguments.contains("--menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.statusMenu?.openMenu() }
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
