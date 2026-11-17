import Foundation
#if canImport(Compression)
import Compression
#endif

// Bogey-Datei (.bogey) – gemeinsames Austauschformat aller Bogey-Club-Apps (siehe README „Dateiformat .bogey“).
// ZIP-Container mit
//   mimetype          "application/vnd.bogeyclub" (unkomprimiert, erster Eintrag)
//   bogey.json        { format:"bogey", version:1, kind:"backup"|"round", app, exportedAt, players, courses, rounds, coursemaps }
//   images/<id>.jpg   Spieler- und Luftbilder
// Ältere Backups der Web-App (reines JSON) werden ebenfalls gelesen.

public enum BogeyFileError: Error, Equatable {
    case notBogey        // weder .bogey noch Bogey-Club-Backup
    case corrupt         // ZIP beschädigt (Prüfsumme, Länge)
    case unsupported     // Kompressionsverfahren unbekannt
    case newerVersion    // aus einer neueren App-Version
}

// MARK: - Inhalt (entspricht den Dokumenten der Web-App)

public struct BogeyPlayer: Codable, Equatable {
    public var id: String
    public var name: String
    public var hcp: Double
    public var hidden: Bool?
    public var photo: String?
    public init(id: String, name: String, hcp: Double, hidden: Bool? = nil, photo: String? = nil) {
        self.id = id; self.name = name; self.hcp = hcp; self.hidden = hidden; self.photo = photo
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        hcp = c.lenientDouble(.hcp) ?? 54
        hidden = try? c.decode(Bool.self, forKey: .hidden)
        photo = try? c.decode(String.self, forKey: .photo)
    }
}

public struct BogeyCourse: Codable, Equatable {
    public var id: String
    public var name: String
    public var cr: Double
    public var slope: Int
    public var pars: [Int]
    public var si: [Int]
    public var mapKey: String?
    public var photo: String?
    public init(id: String, name: String, cr: Double, slope: Int, pars: [Int], si: [Int], mapKey: String? = nil, photo: String? = nil) {
        self.id = id; self.name = name; self.cr = cr; self.slope = slope; self.pars = pars; self.si = si; self.mapKey = mapKey; self.photo = photo
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        cr = c.lenientDouble(.cr) ?? 72
        slope = Int((c.lenientDouble(.slope) ?? 113).rounded())
        pars = (try? c.decode([Int].self, forKey: .pars)) ?? Array(repeating: 4, count: 18)
        si = (try? c.decode([Int].self, forKey: .si)) ?? Array(1...pars.count)
        mapKey = try? c.decode(String.self, forKey: .mapKey)
        photo = try? c.decode(String.self, forKey: .photo)
    }
}

public struct BogeyEntry: Codable, Equatable {
    public var playerId: String
    public var hcp: Double
    /// Schläge je Loch, 0 = Strich / nicht gespielt
    public var strokes: [Int]
    public var tee: String?
    public var cr: Double?
    public var slope: Int?
    public init(playerId: String, hcp: Double, strokes: [Int], tee: String? = nil, cr: Double? = nil, slope: Int? = nil) {
        self.playerId = playerId; self.hcp = hcp; self.strokes = strokes; self.tee = tee; self.cr = cr; self.slope = slope
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        playerId = try c.decode(String.self, forKey: .playerId)
        hcp = c.lenientDouble(.hcp) ?? 54
        strokes = ((try? c.decode([Int?].self, forKey: .strokes)) ?? []).map { $0 ?? 0 }
        tee = try? c.decode(String.self, forKey: .tee)
        cr = c.lenientDouble(.cr)
        slope = c.lenientDouble(.slope).map { Int($0.rounded()) }
    }
}

public struct BogeyRound: Codable, Equatable {
    public var id: String
    public var courseId: String
    /// "yyyy-MM-dd"
    public var date: String
    public var entries: [BogeyEntry]
    public var source: String?
    /// Millisekunden seit 1970
    public var updatedAt: Double?
    public init(id: String, courseId: String, date: String, entries: [BogeyEntry], source: String? = nil, updatedAt: Double? = nil) {
        self.id = id; self.courseId = courseId; self.date = date; self.entries = entries; self.source = source; self.updatedAt = updatedAt
    }
}

public struct BogeyDocument: Codable {
    public enum Kind: String, Codable { case backup, round }
    public var format: String?
    public var version: Int?
    public var kind: Kind
    public var app: String?
    public var exportedAt: String?
    public var players: [BogeyPlayer]
    public var courses: [BogeyCourse]
    public var rounds: [BogeyRound]

    public init(kind: Kind, players: [BogeyPlayer], courses: [BogeyCourse], rounds: [BogeyRound], exportedAt: Date = Date()) {
        self.format = "bogey"; self.version = BogeyFile.version; self.kind = kind; self.app = "Bogey Club"
        self.exportedAt = ISO8601DateFormatter().string(from: exportedAt)
        self.players = players; self.courses = courses; self.rounds = rounds
    }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        format = try? c.decode(String.self, forKey: .format)
        version = try? c.decode(Int.self, forKey: .version)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .backup
        app = try? c.decode(String.self, forKey: .app)
        exportedAt = try? c.decode(String.self, forKey: .exportedAt)
        // Einträge ohne gültige ID überspringen statt die ganze Datei abzulehnen
        players = ((try? c.decode([Lossy<BogeyPlayer>].self, forKey: .players)) ?? []).compactMap(\.value)
        courses = ((try? c.decode([Lossy<BogeyCourse>].self, forKey: .courses)) ?? []).compactMap(\.value)
        rounds = ((try? c.decode([Lossy<BogeyRound>].self, forKey: .rounds)) ?? []).compactMap(\.value)
    }
}

private struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

private extension KeyedDecodingContainer {
    func lenientDouble(_ k: Key) -> Double? {
        if let v = try? decode(Double.self, forKey: k) { return v }
        if let s = try? decode(String.self, forKey: k) { return Double(s.replacingOccurrences(of: ",", with: ".")) }
        return nil
    }
}

// MARK: - Lesen und Schreiben

public enum BogeyFile {
    public static let fileExtension = "bogey"
    public static let mimeType = "application/vnd.bogeyclub"
    public static let typeIdentifier = "club.bogey.file"
    public static let version = 1

    /// Erzeugt eine .bogey-Datei. `images`: Bild-ID → JPEG/PNG-Daten.
    public static func encode(_ doc: BogeyDocument, images: [String: Data] = [:]) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        var entries = [ZipArchive.Entry(name: "mimetype", data: Data(mimeType.utf8), deflate: false),
                       ZipArchive.Entry(name: "bogey.json", data: try enc.encode(doc), deflate: true)]
        for (id, data) in images.sorted(by: { $0.key < $1.key }) where isValidID(id) {
            let ext = data.starts(with: [0x89, 0x50, 0x4E, 0x47]) ? "png" : "jpg"
            entries.append(.init(name: "images/\(id).\(ext)", data: data, deflate: false))
        }
        return ZipArchive.write(entries)
    }

    /// Liest eine .bogey-Datei oder ein altes JSON-Backup. Bilder: ID → Daten.
    public static func decode(_ data: Data) throws -> (document: BogeyDocument, images: [String: Data]) {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x50, 0x4B]) {
            let files = try ZipArchive.read(data)
            guard let json = files["bogey.json"] else { throw BogeyFileError.notBogey }
            let doc: BogeyDocument
            do { doc = try JSONDecoder().decode(BogeyDocument.self, from: json) } catch { throw BogeyFileError.notBogey }
            guard doc.format == "bogey" else { throw BogeyFileError.notBogey }
            if (doc.version ?? 1) > version { throw BogeyFileError.newerVersion }
            var images: [String: Data] = [:]
            for (name, d) in files where name.hasPrefix("images/") {
                let file = String(name.dropFirst("images/".count))
                guard let dot = file.lastIndex(of: ".") else { continue }
                let id = String(file[..<dot])
                if isValidID(id) { images[id] = d }
            }
            return (doc, images)
        }
        // Altes JSON-Backup der Web-App
        guard let doc = try? JSONDecoder().decode(BogeyDocument.self, from: data), doc.app == "Bogey Club" else { throw BogeyFileError.notBogey }
        return (doc, [:])
    }

    public static func isValidID(_ id: String) -> Bool {
        guard (1...200).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || "_-.~:@+".unicodeScalars.contains($0) }
    }
}

// MARK: - ZIP (nur was .bogey braucht: unkomprimiert und Deflate)

public enum ZipArchive {
    public struct Entry {
        public var name: String
        public var data: Data
        public var deflate: Bool
        public init(name: String, data: Data, deflate: Bool) { self.name = name; self.data = data; self.deflate = deflate }
    }

    public static func write(_ entries: [Entry]) -> Data {
        var out = Data(), central = Data()
        let (time, date) = dosDateTime(Date())
        for e in entries {
            let name = Data(e.name.utf8), crc = crc32(e.data)
            var body = e.data, method: UInt16 = 0
            if e.deflate, let z = deflate(e.data), z.count < e.data.count { body = z; method = 8 }
            let offset = UInt32(out.count)
            out.le32(0x04034b50); out.le16(20); out.le16(0x0800); out.le16(method); out.le16(time); out.le16(date)
            out.le32(crc); out.le32(UInt32(body.count)); out.le32(UInt32(e.data.count)); out.le16(UInt16(name.count)); out.le16(0)
            out.append(name); out.append(body)
            central.le32(0x02014b50); central.le16(20); central.le16(20); central.le16(0x0800); central.le16(method)
            central.le16(time); central.le16(date); central.le32(crc); central.le32(UInt32(body.count)); central.le32(UInt32(e.data.count))
            central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0); central.le32(0); central.le32(offset)
            central.append(name)
        }
        let cOffset = UInt32(out.count)
        out.append(central)
        out.le32(0x06054b50); out.le16(0); out.le16(0); out.le16(UInt16(entries.count)); out.le16(UInt16(entries.count))
        out.le32(UInt32(central.count)); out.le32(cOffset); out.le16(0)
        return out
    }

    public static func read(_ data: Data) throws -> [String: Data] {
        let b = [UInt8](data)
        func u16(_ i: Int) throws -> Int { guard i + 2 <= b.count else { throw BogeyFileError.corrupt }; return Int(b[i]) | Int(b[i + 1]) << 8 }
        func u32(_ i: Int) throws -> Int { guard i + 4 <= b.count else { throw BogeyFileError.corrupt }; return try u16(i) | u16(i + 2) << 16 }
        guard b.count >= 22 else { throw BogeyFileError.notBogey }
        var end = -1
        var i = b.count - 22
        while i >= max(0, b.count - 65_557) { if try u32(i) == 0x06054b50 { end = i; break }; i -= 1 }
        guard end >= 0 else { throw BogeyFileError.notBogey }
        let count = try u16(end + 10)
        var p = try u32(end + 16)
        var files: [String: Data] = [:]
        for _ in 0..<count {
            guard try u32(p) == 0x02014b50 else { throw BogeyFileError.corrupt }
            let method = try u16(p + 10), crc = try u32(p + 16), csize = try u32(p + 20), size = try u32(p + 24)
            let nlen = try u16(p + 28), xlen = try u16(p + 30), clen = try u16(p + 32), lho = try u32(p + 42)
            guard p + 46 + nlen <= b.count else { throw BogeyFileError.corrupt }
            let name = String(decoding: b[(p + 46)..<(p + 46 + nlen)], as: UTF8.self)
            p += 46 + nlen + xlen + clen
            if name.hasSuffix("/") { continue }
            let start = lho + 30 + (try u16(lho + 26)) + (try u16(lho + 28))
            guard start >= 0, start + csize <= b.count else { throw BogeyFileError.corrupt }
            let raw = Data(b[start..<(start + csize)])
            let content: Data
            switch method {
            case 0: content = raw
            case 8: guard let d = inflate(raw, size: size) else { throw BogeyFileError.corrupt }; content = d
            default: throw BogeyFileError.unsupported
            }
            guard content.count == size, Int(crc32(content)) == crc else { throw BogeyFileError.corrupt }
            files[name] = content
        }
        return files
    }

    // MARK: Hilfen

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ d: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in d { c = crcTable[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    private static func dosDateTime(_ d: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        let time = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let date = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (time, date)
    }

    /// Roh-Deflate (RFC 1951) – COMPRESSION_ZLIB von Apple erzeugt genau das, ohne zlib-Kopf.
    static func deflate(_ d: Data) -> Data? {
        #if canImport(Compression)
        guard !d.isEmpty else { return nil }
        let cap = d.count + 1024
        var out = Data(count: cap)
        let n = out.withUnsafeMutableBytes { o in
            d.withUnsafeBytes { i in
                compression_encode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, cap, i.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { return nil }
        out.count = n
        return out
        #else
        return nil
        #endif
    }

    static func inflate(_ d: Data, size: Int) -> Data? {
        if size == 0 { return Data() }
        #if canImport(Compression)
        guard !d.isEmpty else { return nil }
        var out = Data(count: size)
        let n = out.withUnsafeMutableBytes { o in
            d.withUnsafeBytes { i in
                compression_decode_buffer(o.bindMemory(to: UInt8.self).baseAddress!, size, i.bindMemory(to: UInt8.self).baseAddress!, d.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n == size else { return nil }
        return out
        #else
        return nil
        #endif
    }
}

private extension Data {
    mutating func le16(_ v: UInt16) { append(UInt8(v & 0xFF)); append(UInt8(v >> 8)) }
    mutating func le32(_ v: UInt32) { le16(UInt16(v & 0xFFFF)); le16(UInt16(v >> 16)) }
}
