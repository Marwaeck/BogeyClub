import XCTest
@testable import BogeyScan

final class BogeyFileTests: XCTestCase {
    /// Von der Web-App erzeugte Runde (Deflate über CompressionStream, Bild unkomprimiert, null und "36,0" als Werte)
    private let webRound = Data(base64Encoded: "UEsDBBQAAAgAAHWUcV2tUfqdGQAAABkAAAAIAAAAbWltZXR5cGVhcHBsaWNhdGlvbi92bmQuYm9nZXljbHViUEsDBBQAAAgIAHWUcV2yTQgxggEAALYCAAAKAAAAYm9nZXkuanNvbm2SP2/bMBDFv4rwphZ4NkhZfxxudoYgQ5ciUw0Nss3YQmiRoKi0qaHvXoiOKw3hciB57+7dj7zi1fpLHaCwtyf9AeJd+66xLZQk3pr2CAVv+/YIonYOCtsxMXk0/R6E/uOsD/q4GUukIi0WUi5k+SLXSgglxFII8QuEM/WH9h3U7opmrOk2EkRbXzQUNm1bJ1vddK7RBsT54KDkepkR7myDhUJzOUkMvKu36aTe6jb50XdB+7sUq4ICQ0UcbO87PesbdBecqcPfxUmb/VTk6TF5uV8l35602X8HcfBQpVhKojPWaSiZrglXx0kyZlwx5/9YEV0Dtcsp+cAVS6ZcM2NRjVYixZkTPwK4+Xv+0tmxDnpONQfRu/E04pblQybui9Bt8M3npDfazxPnGdAuePsW8/Lou6CIMxRse2OqEfFcHkFH+aqYiwuWzFiyYMF8jBUR9Oj3pw2f5Ipymc/IiaGanuRSuw7qOk09bt7jr/sNJQVxvoVXqF1FnK2JfathGP4BUEsDBBQAAAgAAHWUcV0A1ni+CwAAAAsAAAAPAAAAaW1hZ2VzL2ltZzEuanBn/9j/4AECAwQF/9lQSwECFAAUAAAIAAB1lHFdrVH6nRkAAAAZAAAACAAAAAAAAAAAAAAAAAAAAAAAbWltZXR5cGVQSwECFAAUAAAICAB1lHFdsk0IMYIBAAC2AgAACgAAAAAAAAAAAAAAAAA/AAAAYm9nZXkuanNvblBLAQIUABQAAAgAAHWUcV0A1ni+CwAAAAsAAAAPAAAAAAAAAAAAAAAAAOkBAABpbWFnZXMvaW1nMS5qcGdQSwUGAAAAAAMAAwCrAAAAIQIAAAAA")!

    func testReadsFileWrittenByWebApp() throws {
        let (doc, images) = try BogeyFile.decode(webRound)
        XCTAssertEqual(doc.kind, .round)
        XCTAssertEqual(doc.players.map(\.name), ["Anna Beispiel", "Ben Muster"])
        XCTAssertEqual(doc.players[1].hcp, 36)
        XCTAssertEqual(doc.courses.first?.pars.count, 9)
        XCTAssertEqual(doc.rounds.first?.entries.first?.strokes, [5, 4, 3, 6, 0, 5, 4, 6, 0])
        XCTAssertEqual(doc.rounds.first?.entries.last?.tee, "Rot")
        XCTAssertEqual(doc.rounds.first?.entries.last?.slope, 120)
        XCTAssertEqual(images["img1"], Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, 5, 0xFF, 0xD9]))
    }

    func testRoundTrip() throws {
        let doc = BogeyDocument(kind: .backup,
            players: [BogeyPlayer(id: "p1", name: "Jörg Ü", hcp: 23.5)],
            courses: [BogeyCourse(id: "c1", name: "Platz", cr: 71.2, slope: 131, pars: Array(repeating: 4, count: 18), si: Array(1...18))],
            rounds: [BogeyRound(id: "r1", courseId: "c1", date: "2026-11-17", entries: [BogeyEntry(playerId: "p1", hcp: 23.5, strokes: Array(repeating: 5, count: 18))], updatedAt: 1)])
        let data = try BogeyFile.encode(doc, images: ["p1foto": Data(repeating: 7, count: 300)])
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B])
        let files = try ZipArchive.read(data)
        XCTAssertEqual(String(decoding: files["mimetype"]!, as: UTF8.self), BogeyFile.mimeType)
        let (back, images) = try BogeyFile.decode(data)
        XCTAssertEqual(back.players, doc.players)
        XCTAssertEqual(back.courses, doc.courses)
        XCTAssertEqual(back.rounds, doc.rounds)
        XCTAssertEqual(images["p1foto"]?.count, 300)
        XCTAssertEqual(back.format, "bogey")
    }

    func testDeflateRoundTrip() throws {
        let text = Data(String(repeating: "Bogey Club Scorekarte ", count: 500).utf8)
        let zip = ZipArchive.write([.init(name: "a.txt", data: text, deflate: true)])
        XCTAssertLessThan(zip.count, text.count / 2)
        XCTAssertEqual(try ZipArchive.read(zip)["a.txt"], text)
    }

    func testLegacyJSONBackup() throws {
        let json = #"{"app":"Bogey Club","kind":"backup","version":2,"players":[{"id":"a","name":"A","hcp":10}],"courses":[],"rounds":[],"images":{"x":"data:image/jpeg;base64,AA=="}}"#
        let (doc, images) = try BogeyFile.decode(Data(json.utf8))
        XCTAssertEqual(doc.players.count, 1)
        XCTAssertTrue(images.isEmpty)
    }

    func testRejectsForeignFiles() {
        XCTAssertThrowsError(try BogeyFile.decode(Data(#"{"hello":1}"#.utf8)))
        XCTAssertThrowsError(try BogeyFile.decode(Data([0x50, 0x4B, 3, 4, 9, 9, 9])))
        let otherZip = ZipArchive.write([.init(name: "readme.txt", data: Data("x".utf8), deflate: false)])
        XCTAssertThrowsError(try BogeyFile.decode(otherZip)) { XCTAssertEqual($0 as? BogeyFileError, .notBogey) }
    }

    func testCorruptCRC() throws {
        var zip = ZipArchive.write([.init(name: "a.txt", data: Data("hallo".utf8), deflate: false)])
        zip[30 + 5] ^= 0xFF   // erstes Byte des Inhalts
        XCTAssertThrowsError(try ZipArchive.read(zip)) { XCTAssertEqual($0 as? BogeyFileError, .corrupt) }
    }

    func testNewerVersionRejected() throws {
        let json = Data(#"{"format":"bogey","version":9,"kind":"backup","players":[],"courses":[],"rounds":[]}"#.utf8)
        let zip = ZipArchive.write([.init(name: "bogey.json", data: json, deflate: false)])
        XCTAssertThrowsError(try BogeyFile.decode(zip)) { XCTAssertEqual($0 as? BogeyFileError, .newerVersion) }
    }
}
