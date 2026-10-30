import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window: an AppKit tab view in toolbar style (the standard
/// macOS settings look) with a SwiftUI form in each tab.
@MainActor
final class SettingsWindowController {
    private let dictation: Dictation
    private let replacements = ReplacementsStore()
    private var window: NSWindow?

    init(dictation: Dictation) {
        self.dictation = dictation
    }

    func show(tab index: Int? = nil) {
        // The file may have been edited by hand since the window last opened.
        replacements.reload()
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettings(dictation: dictation).frame(width: 520, height: 300)))
            tabs.addTabViewItem(tab("Replacements", symbol: "character.cursor.ibeam", ReplacementsSettings(store: replacements).frame(width: 520, height: 420)))
            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let index, let tabs = window?.contentViewController as? NSTabViewController {
            tabs.selectedTabViewItemIndex = index
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func tab(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: view)
        // Each tab sizes the window to fit, and its title becomes the window title.
        controller.sizingOptions = .preferredContentSize
        controller.title = label
        let item = NSTabViewItem(viewController: controller)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

// MARK: - General

struct GeneralSettings: View {
    @Bindable var dictation: Dictation
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker("Dictation key", selection: $dictation.key) {
                    ForEach(TriggerKey.allCases, id: \.self) { key in
                        Label(key.title, systemImage: key.symbolName).tag(key)
                    }
                }
            } footer: {
                Text("Hold the key to talk and let go to paste. Double-press for hands-free, then press again to stop. A quick tap still does whatever macOS does with the key.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Remove “uh” and “um”", isOn: $dictation.removeFillers)
            } footer: {
                Text("Takes out uh, um, erm and hmm. Nothing else in what you said is changed.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            Storage.appendToLog("open at login: \(error)")
                        }
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Replacements

/// The rows of replacements.txt, saved back to the file on every edit.
@MainActor
@Observable
final class ReplacementsStore {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var heard: String
        var written: String
    }

    var rows: [Row] = [] {
        didSet { Storage.saveReplacements(rows.map { .init(heard: $0.heard, written: $0.written) }) }
    }

    func reload() {
        let loaded = Storage.loadReplacements().map { Row(heard: $0.heard, written: $0.written) }
        // Keep the rows (and their ids) when nothing changed on disk, so the
        // table doesn't lose its selection, and skip the save that would follow.
        if loaded.map(\.heard) != rows.map(\.heard) || loaded.map(\.written) != rows.map(\.written) {
            rows = loaded
        }
    }

    func binding(for id: Row.ID, _ field: WritableKeyPath<Row, String>) -> Binding<String> {
        Binding(
            get: { self.rows.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { value in
                guard let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
                self.rows[index][keyPath: field] = value
            }
        )
    }
}

struct ReplacementsSettings: View {
    let store: ReplacementsStore
    @State private var selection = Set<ReplacementsStore.Row.ID>()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("For names and words Vocal gets wrong. Whole words only; capitals on the left don't matter. Changes apply to the next dictation.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                Table(store.rows, selection: $selection) {
                    TableColumn("Vocal writes") { row in
                        TextField("Vocal writes", text: store.binding(for: row.id, \.heard))
                            .labelsHidden()
                    }
                    TableColumn("You want") { row in
                        TextField("You want", text: store.binding(for: row.id, \.written))
                            .labelsHidden()
                    }
                }
                Divider()
                HStack(spacing: 0) {
                    Button {
                        let row = ReplacementsStore.Row(heard: "", written: "")
                        store.rows.append(row)
                        selection = [row.id]
                    } label: {
                        Image(systemName: "plus").frame(width: 24, height: 20)
                    }
                    .help("Add a replacement")
                    Divider().frame(height: 16)
                    Button {
                        store.rows.removeAll { selection.contains($0.id) }
                        selection = []
                    } label: {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selection.isEmpty)
                    .help("Remove the selected replacements")
                    Spacer()
                    Button("Show File") {
                        NSWorkspace.shared.activateFileViewerSelecting([Storage.replacements])
                    }
                    .padding(.trailing, 6)
                }
                .buttonStyle(.borderless)
                .padding(4)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
        }
        .padding(20)
    }
}
