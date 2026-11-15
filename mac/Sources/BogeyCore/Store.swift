import Foundation

/// Datenablage der Mac-App: alle Collections (Spieler, Plätze, Runden, Platzkarten) in einer
/// JSON-Datei, Bilder als einzelne Dateien. Liegt unter ~/Library/Application Support/Bogey Club.
/// Einmal pro Tag wird vor der ersten Änderung eine Kopie unter „Sicherungen“ abgelegt (die letzten 30).
public final class Store {
    public let folder: URL
    public var dataFile: URL { folder.appendingPathComponent("daten.json") }
    public var photosFolder: URL { folder.appendingPathComponent("Bilder", isDirectory: true) }
    public var backupsFolder: URL { folder.appendingPathComponent("Sicherungen", isDirectory: true) }

    /// coll -> id -> Dokument
    private var data: [String: [String: Any]] = [:]
    private var backedUpToday = false
    private let fm = FileManager.default

    public static var defaultFolder: URL {
        if let custom = ProcessInfo.processInfo.environment["BOGEY_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Bogey Club", isDirectory: true)
    }

    public init(folder: URL = Store.defaultFolder) throws {
        self.folder = folder
        try fm.createDirectory(at: photosFolder, withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: dataFile) {
            guard let obj = try JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
                throw StoreError.unreadable
            }
            for (coll, docs) in obj {
                if let docs = docs as? [String: Any] { data[coll] = docs }
            }
        }
    }

    public enum StoreError: Error { case unreadable, badId, badData }

    // MARK: Dokumente

    /// Alle Daten als JSON-Text (für die Web-Oberfläche).
    public func allJSON() throws -> String {
        let raw = try JSONSerialization.data(withJSONObject: data, options: [])
        return String(decoding: raw, as: UTF8.self)
    }

    public func documents(_ coll: String) -> [String: Any] { data[coll] ?? [:] }

    public func set(_ coll: String, id: String, json: String) throws {
        guard Store.validId(coll), Store.validId(id) else { throw StoreError.badId }
        guard let doc = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw StoreError.badData
        }
        data[coll, default: [:]][id] = doc
        try persist()
    }

    public func delete(_ coll: String, id: String) throws {
        guard data[coll]?[id] != nil else { return }
        data[coll]?[id] = nil
        try persist()
    }

    private func persist() throws {
        backupOncePerDay()
        let raw = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys])
        try raw.write(to: dataFile, options: .atomic)
    }

    private func backupOncePerDay() {
        guard !backedUpToday, fm.fileExists(atPath: dataFile.path) else { return }
        backedUpToday = true
        let day = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withFullDate])
        let target = backupsFolder.appendingPathComponent("daten-\(day).json")
        try? fm.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: target.path) { try? fm.copyItem(at: dataFile, to: target) }
        // nur die letzten 30 Tage behalten
        if let files = try? fm.contentsOfDirectory(atPath: backupsFolder.path).filter({ $0.hasPrefix("daten-") }).sorted(),
           files.count > 30 {
            for f in files.prefix(files.count - 30) { try? fm.removeItem(at: backupsFolder.appendingPathComponent(f)) }
        }
    }

    // MARK: Bilder

    private static let extensions = ["image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif"]
    private static let types = Dictionary(uniqueKeysWithValues: extensions.map { ($1, $0) })

    /// Speichert ein Bild und gibt seine neue ID zurück.
    public func addPhoto(_ bytes: Data, type: String) throws -> String {
        guard let ext = Store.extensions[type] else { throw StoreError.badData }
        let id = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        try bytes.write(to: photosFolder.appendingPathComponent("\(id).\(ext)"), options: .atomic)
        return id
    }

    /// Bilddatei und MIME-Typ zu einer ID, falls vorhanden.
    public func photo(_ id: String) -> (url: URL, type: String)? {
        guard Store.validId(id) else { return nil }
        for (ext, type) in Store.types {
            let url = photosFolder.appendingPathComponent("\(id).\(ext)")
            if fm.fileExists(atPath: url.path) { return (url, type) }
        }
        return nil
    }

    public func deletePhoto(_ id: String) {
        if let p = photo(id) { try? fm.removeItem(at: p.url) }
    }

    /// Wie in der Web-App: nur einfache Zeichen, keine Pfade.
    public static func validId(_ id: String) -> Bool {
        guard (1...200).contains(id.count), id != ".", id != ".." else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.~:@+")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
