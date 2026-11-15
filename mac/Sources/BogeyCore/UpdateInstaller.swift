import Foundation

/// Tauscht eine App gegen die Version aus einer heruntergeladenen ZIP (ohne Oberfläche, testbar).
/// Prüft vorher: richtige App (Bundle-ID), erwartete Version, intakte Signatur. Bei einem Fehler
/// bleibt die alte App unverändert an ihrem Platz.
public enum UpdateInstaller {
    public enum Failure: Error, Equatable { case noApp, wrongApp, wrongVersion, damaged, toolFailed(String) }

    public static func install(zip: URL, replacing target: URL, bundleID: String, version: String) throws {
        let fm = FileManager.default
        // Auf demselben Laufwerk wie die App arbeiten, damit der Austausch ein einfaches Umbenennen ist
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: target, create: true)
        defer { try? fm.removeItem(at: work) }

        let unpacked = work.appendingPathComponent("neu", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        guard let newApp = try fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }),
              let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) else { throw Failure.noApp }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw Failure.wrongApp }
        guard info["CFBundleShortVersionString"] as? String == version else { throw Failure.wrongVersion }
        do { try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path]) } catch { throw Failure.damaged }
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])

        let old = work.appendingPathComponent("alt.app")
        try fm.moveItem(at: target, to: old)
        do { try fm.moveItem(at: newApp, to: target) } catch { try? fm.moveItem(at: old, to: target); throw error }
    }

    static func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw Failure.toolFailed((tool as NSString).lastPathComponent) }
    }
}
