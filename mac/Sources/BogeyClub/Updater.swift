import AppKit
import BogeyCore

/// Updater der Mac-App: fragt die neueste Version bei GitHub (Releases) ab, lädt die Mac-ZIP,
/// prüft sie, tauscht die App aus und startet sie neu. Daten im Datenordner bleiben unberührt.
/// Automatisch höchstens einmal am Tag beim Start; jederzeit über „Nach Updates suchen …“.
@MainActor
final class Updater {
    static let shared = Updater()
    private let defaults = UserDefaults.standard
    private var busy = false
    private var progressWindow: NSWindow?

    var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
    var automatic: Bool {
        get { defaults.object(forKey: "updateAutomatic") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "updateAutomatic") }
    }

    /// Beim Start: still prüfen, wenn eingeschaltet und seit einem Tag nicht mehr geprüft.
    func checkOnLaunch() {
        guard automatic else { return }
        let last = defaults.double(forKey: "updateLastCheck")
        guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        Task { await check(interactive: false) }
    }

    func check(interactive: Bool) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        defaults.set(Date().timeIntervalSince1970, forKey: "updateLastCheck")

        var request = URLRequest(url: UpdateCheck.latestURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("BogeyClub-Mac/\(current)", forHTTPHeaderField: "User-Agent")
        let release: Release
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if status == 404 {
                if interactive { info("Du hast die neueste Version.", "Bogey Club \(current) – auf GitHub ist noch keine neuere Version veröffentlicht.") }
                return
            }
            guard status == 200 else { throw URLError(.badServerResponse) }
            release = try UpdateCheck.parse(data, assetPrefix: "Bogey-Club-mac-")
        } catch {
            if interactive { info("Keine Verbindung zu GitHub.", "Die Suche nach Updates braucht Internet. Bitte später erneut versuchen.") }
            return
        }

        guard UpdateCheck.isNewer(release.version, than: current) else {
            if interactive { info("Du hast die neueste Version.", "Bogey Club \(current) ist aktuell.") }
            return
        }
        if !interactive, defaults.string(forKey: "updateSkip") == release.version { return }

        let alert = NSAlert()
        alert.messageText = "Bogey Club \(release.version) ist verfügbar"
        var text = "Installiert ist \(current). Deine Spieler, Plätze und Runden bleiben erhalten."
        if !release.notes.isEmpty { text += "\n\nNeu:\n" + String(release.notes.prefix(700)) }
        alert.informativeText = text
        alert.addButton(withTitle: release.assetURL == nil ? "Download-Seite öffnen" : "Jetzt installieren")
        alert.addButton(withTitle: "Später")
        alert.addButton(withTitle: "Diese Version überspringen")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = release.assetURL { await install(release, from: url) } else { NSWorkspace.shared.open(release.pageURL) }
        case .alertThirdButtonReturn:
            defaults.set(release.version, forKey: "updateSkip")
        default: break
        }
    }

    // MARK: Installieren

    private func install(_ release: Release, from url: URL) async {
        showProgress("Bogey Club \(release.version) wird geladen …")
        defer { hideProgress() }
        let fm = FileManager.default
        let target = Bundle.main.bundleURL
        do {
            let (download, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw URLError(.badServerResponse) }
            let zip = fm.temporaryDirectory.appendingPathComponent("Bogey-Club-Update-\(release.version).zip")
            try? fm.removeItem(at: zip)
            try fm.moveItem(at: download, to: zip)
            defer { try? fm.removeItem(at: zip) }
            try UpdateInstaller.install(zip: zip, replacing: target, bundleID: Bundle.main.bundleIdentifier ?? "club.bogey.mac", version: release.version)

            hideProgress()
            relaunch(target)
        } catch {
            hideProgress()
            let alert = NSAlert()
            alert.messageText = "Das Update konnte nicht installiert werden."
            alert.informativeText = "Lade die neue Version bitte von der Download-Seite und ersetze die App im Ordner „Programme“. Deine Daten bleiben dabei erhalten."
            alert.addButton(withTitle: "Download-Seite öffnen"); alert.addButton(withTitle: "Abbrechen")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
        }
    }

    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    // MARK: Hinweise

    private func info(_ title: String, _ text: String) {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text; alert.runModal()
    }

    private func showProgress(_ text: String) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 90), styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Update"
        let label = NSTextField(labelWithString: text); label.frame = NSRect(x: 20, y: 50, width: 320, height: 20)
        let bar = NSProgressIndicator(frame: NSRect(x: 20, y: 20, width: 320, height: 20))
        bar.isIndeterminate = true; bar.style = .bar; bar.startAnimation(nil)
        w.contentView?.addSubview(label); w.contentView?.addSubview(bar)
        w.center(); w.makeKeyAndOrderFront(nil)
        progressWindow = w
    }

    private func hideProgress() { progressWindow?.orderOut(nil); progressWindow = nil }
}
