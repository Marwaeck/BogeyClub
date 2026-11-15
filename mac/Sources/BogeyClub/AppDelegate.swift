import AppKit
import BogeyCore
import BogeyScan

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var web: WebController?
    private var store: Store?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        do {
            store = try Store()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Die Bogey-Club-Daten konnten nicht geöffnet werden."
            alert.informativeText = "Die Datei „daten.json“ im Datenordner ist beschädigt. Im Unterordner „Sicherungen“ liegen tägliche Kopien.\n\(Store.defaultFolder.path)"
            alert.addButton(withTitle: "Datenordner zeigen")
            alert.addButton(withTitle: "Beenden")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(Store.defaultFolder) }
            NSApp.terminate(nil)
            return
        }

        Task.detached(priority: .utility) { ScorecardReader.warmUp() }

        let web = WebController(store: store!)
        self.web = web
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Bogey Club"
        window.minSize = NSSize(width: 420, height: 520)
        window.contentViewController = web
        window.center()
        window.setFrameAutosaveName("BogeyClubMain")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menüs

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "Über Bogey Club", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Datenordner im Finder zeigen", action: #selector(showDataFolder), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Bogey Club ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Andere ausblenden", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Alle einblenden", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Bogey Club beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Bearbeiten")
        edit.addItem(withTitle: "Widerrufen", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Wiederholen", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Ausschneiden", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Kopieren", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Einsetzen", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "Darstellung")
        view.addItem(withTitle: "Neu laden", action: #selector(reload), keyEquivalent: "r")
        view.addItem(.separator())
        view.addItem(withTitle: "Originalgröße", action: #selector(zoomReset), keyEquivalent: "0")
        view.addItem(withTitle: "Vergrößern", action: #selector(zoomIn), keyEquivalent: "+")
        view.addItem(withTitle: "Verkleinern", action: #selector(zoomOut), keyEquivalent: "-")
        view.addItem(.separator())
        let fs = view.addItem(withTitle: "Vollbild", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewItem.submenu = view

        let windowItem = NSMenuItem(); main.addItem(windowItem)
        let win = NSMenu(title: "Fenster")
        win.addItem(withTitle: "Im Dock ablegen", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoomen", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(withTitle: "Bogey Club", action: #selector(showWindow), keyEquivalent: "1")
        windowItem.submenu = win
        NSApp.windowsMenu = win

        NSApp.mainMenu = main
    }

    @objc private func showDataFolder() { NSWorkspace.shared.open(store?.folder ?? Store.defaultFolder) }
    @objc private func reload() { web?.reload() }
    @objc private func zoomReset() { web?.zoom(to: 1) }
    @objc private func zoomIn() { web?.zoom(by: 0.1) }
    @objc private func zoomOut() { web?.zoom(by: -0.1) }
    @objc private func showWindow() { window?.makeKeyAndOrderFront(nil) }
}
