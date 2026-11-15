import XCTest
@testable import BogeyCore

final class StoreTests: XCTestCase {
    func testRoundTripAndPhotos() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bogey-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = try Store(folder: dir)
        try s.set("players", id: "abc123", json: #"{"name":"Marcel","hcp":18.4,"hidden":false}"#)
        try s.set("rounds", id: "r1", json: #"{"date":"2026-11-15","entries":[]}"#)
        try s.delete("rounds", id: "r1")
        XCTAssertThrowsError(try s.set("players", id: "../x", json: "{}"))

        let again = try Store(folder: dir)
        let json = try again.allJSON()
        XCTAssertTrue(json.contains(#""hidden":false"#))
        XCTAssertEqual(again.documents("rounds").count, 0)

        let id = try again.addPhoto(Data([0xFF, 0xD8, 0xFF]), type: "image/jpeg")
        XCTAssertEqual(again.photo(id)?.type, "image/jpeg")
        again.deletePhoto(id)
        XCTAssertNil(again.photo(id))
        XCTAssertNil(again.photo("../daten"))
    }
}

final class UpdateCheckTests: XCTestCase {
    func testVersions() {
        XCTAssertTrue(UpdateCheck.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(UpdateCheck.isNewer("1.10", than: "1.9.9"))
        XCTAssertTrue(UpdateCheck.isNewer("2.0.0", than: "1.99"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("1.0.0-beta", than: "1.0.0"))
        XCTAssertFalse(UpdateCheck.isNewer("0.9", than: "1.0.0"))
    }

    func testParseRelease() throws {
        let json = #"""
        {"tag_name":"v1.2.0","html_url":"https://github.com/Marwaeck/BogeyClub/releases/tag/v1.2.0","body":"- Neu: Updater\n",
         "assets":[{"name":"Bogey-Club-windows-1.2.0.zip","browser_download_url":"https://example.org/w.zip","size":10},
                   {"name":"Bogey-Club-mac-1.2.0.zip","browser_download_url":"https://example.org/m.zip","size":20}]}
        """#
        let r = try UpdateCheck.parse(Data(json.utf8), assetPrefix: "Bogey-Club-mac-")
        XCTAssertEqual(r.version, "1.2.0")
        XCTAssertEqual(r.assetURL?.absoluteString, "https://example.org/m.zip")
        XCTAssertEqual(r.assetSize, 20)
        XCTAssertEqual(r.notes, "- Neu: Updater")
        let none = try UpdateCheck.parse(Data(#"{"tag_name":"1.3","html_url":"https://x.y/","assets":[]}"#.utf8), assetPrefix: "Bogey-Club-mac-")
        XCTAssertEqual(none.version, "1.3"); XCTAssertNil(none.assetURL)
        XCTAssertThrowsError(try UpdateCheck.parse(Data("[]".utf8), assetPrefix: "x"))
    }
}

final class UpdateInstallerTests: XCTestCase {
    private let fm = FileManager.default

    /// Kleine, lokal signierte Test-App mit Bundle-ID und Version.
    private func makeApp(in dir: URL, version: String, id: String = "club.bogey.test") throws -> URL {
        let app = dir.appendingPathComponent("Test.app")
        try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleShortVersionString": version, "CFBundleExecutable": "Test", "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: app.appendingPathComponent("Contents/Info.plist"))
        try "#!/bin/sh\necho \(version)\n".write(to: app.appendingPathComponent("Contents/MacOS/Test"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: app.appendingPathComponent("Contents/MacOS/Test").path)
        try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
        return app
    }

    private func zip(_ app: URL, to zip: URL) throws { try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path]) }
    private func version(_ app: URL) -> String? { NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))?["CFBundleShortVersionString"] as? String }

    func testInstallReplacesAppAndRejectsBadUpdates() throws {
        let root = fm.temporaryDirectory.appendingPathComponent("bogey-upd-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let installed = try makeApp(in: root.appendingPathComponent("Programme"), version: "1.0.0")
        let next = try makeApp(in: root.appendingPathComponent("neu"), version: "1.1.0")
        let good = root.appendingPathComponent("good.zip"); try zip(next, to: good)

        // Falsche Version oder falsche App: nichts wird ersetzt
        XCTAssertThrowsError(try UpdateInstaller.install(zip: good, replacing: installed, bundleID: "club.bogey.test", version: "1.2.0")) { XCTAssertEqual($0 as? UpdateInstaller.Failure, .wrongVersion) }
        XCTAssertThrowsError(try UpdateInstaller.install(zip: good, replacing: installed, bundleID: "club.bogey.other", version: "1.1.0")) { XCTAssertEqual($0 as? UpdateInstaller.Failure, .wrongApp) }
        XCTAssertEqual(version(installed), "1.0.0")

        // Nachträglich verändert: Signatur passt nicht mehr
        let tampered = try makeApp(in: root.appendingPathComponent("kaputt"), version: "1.1.0")
        try "#!/bin/sh\necho boese\n".write(to: tampered.appendingPathComponent("Contents/MacOS/Test"), atomically: true, encoding: .utf8)
        let bad = root.appendingPathComponent("bad.zip"); try zip(tampered, to: bad)
        XCTAssertThrowsError(try UpdateInstaller.install(zip: bad, replacing: installed, bundleID: "club.bogey.test", version: "1.1.0")) { XCTAssertEqual($0 as? UpdateInstaller.Failure, .damaged) }
        XCTAssertEqual(version(installed), "1.0.0")

        // Gutes Update wird installiert
        try UpdateInstaller.install(zip: good, replacing: installed, bundleID: "club.bogey.test", version: "1.1.0")
        XCTAssertEqual(version(installed), "1.1.0")
    }
}
