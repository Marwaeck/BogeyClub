import XCTest
#if canImport(AppKit)
import AppKit
#endif
@testable import BogeyScan

final class ParserTests: XCTestCase {
    /// Erzeugt Wörter einer Tabellenzeile: Beschriftung links, Werte in gleichmäßigen Spalten.
    private func row(_ label: String, _ values: [String], y: CGFloat, firstX: CGFloat = 0.2, step: CGFloat = 0.035) -> [OCRToken] {
        var t: [OCRToken] = []
        if !label.isEmpty { t.append(OCRToken(label, CGRect(x: 0.02, y: y, width: 0.1, height: 0.03))) }
        for (i, v) in values.enumerated() where !v.isEmpty {
            t.append(OCRToken(v, CGRect(x: firstX + CGFloat(i) * step - 0.01, y: y, width: 0.02, height: 0.03)))
        }
        return t
    }

    func testEighteenHolesWithSumColumnsAndBlank() {
        let holes = (1...9).map(String.init) + ["Out"] + (10...18).map(String.init) + ["In", "Total"]
        let par = ["4", "5", "3", "4", "4", "3", "5", "4", "4", "36", "4", "4", "3", "5", "4", "4", "3", "5", "4", "36", "72"]
        let si = ["7", "1", "15", "9", "3", "17", "5", "11", "13", "", "8", "2", "16", "10", "4", "18", "6", "12", "14", "", ""]
        let marcel = ["5", "6", "3", "5", "", "4", "6", "5", "4", "38", "5", "5", "4", "6", "5", "4", "3", "6", "5", "43", "81"]
        let anna = ["4", "5", "4", "4", "5", "3", "5", "5", "4", "39", "5", "4", "3", "6", "4", "5", "3", "5", "5", "40", "79"]
        var tokens: [OCRToken] = [OCRToken("Golfclub Bruchsal", CGRect(x: 0.3, y: 0.92, width: 0.3, height: 0.03)),
                                  OCRToken("15.11.2026", CGRect(x: 0.7, y: 0.92, width: 0.1, height: 0.03))]
        tokens += row("Loch", holes, y: 0.8)
        tokens += row("Gelb", ["312", "455", "160", "350", "330", "140", "480", "360", "340", "2927"], y: 0.75)
        tokens += row("Par", par, y: 0.7)
        tokens += row("Hcp", si, y: 0.65)
        tokens += row("Marcel 18,4", marcel, y: 0.6)
        tokens += row("Anna", anna, y: 0.55)
        tokens += row("Punkte", ["2", "2", "3", "2", "0", "2", "2", "1", "2"], y: 0.5)

        let r = ScorecardParser.parse(pages: [tokens])
        XCTAssertEqual(r.course, "Golfclub Bruchsal")
        XCTAssertEqual(r.date, "2026-11-15")
        XCTAssertEqual(r.par, [4, 5, 3, 4, 4, 3, 5, 4, 4, 4, 4, 3, 5, 4, 4, 3, 5, 4])
        XCTAssertEqual(r.strokeIndex, [7, 1, 15, 9, 3, 17, 5, 11, 13, 8, 2, 16, 10, 4, 18, 6, 12, 14])
        XCTAssertEqual(r.players.map(\.name), ["Marcel", "Anna"])
        XCTAssertEqual(r.players[0].strokes, [5, 6, 3, 5, 0, 4, 6, 5, 4, 5, 5, 4, 6, 5, 4, 3, 6, 5])
        XCTAssertEqual(r.players[1].strokes.count, 18)
    }

    func testTwoHalvesAreMerged() {
        var tokens: [OCRToken] = []
        tokens += row("Loch", (1...9).map(String.init), y: 0.9)
        tokens += row("Par", ["4", "4", "3", "5", "4", "4", "3", "5", "4"], y: 0.85)
        tokens += row("Tom", ["5", "5", "4", "6", "5", "5", "4", "6", "5"], y: 0.8)
        tokens += row("Loch", (10...18).map(String.init), y: 0.5)
        tokens += row("Par", ["4", "3", "5", "4", "4", "3", "5", "4", "4"], y: 0.45)
        tokens += row("Tom", ["6", "4", "6", "5", "5", "4", "6", "5", "5"], y: 0.4)
        let r = ScorecardParser.parse(pages: [tokens])
        XCTAssertEqual(r.par.count, 18)
        XCTAssertEqual(r.players.count, 1)
        XCTAssertEqual(r.players[0].strokes, [5, 5, 4, 6, 5, 5, 4, 6, 5, 6, 4, 6, 5, 5, 4, 6, 5, 5])
    }

    func testNineHolesWithoutHoleRow() {
        var tokens: [OCRToken] = []
        tokens += row("Par", ["4", "4", "3", "5", "4", "4", "3", "5", "4", "36"], y: 0.85)
        tokens += row("Lisa", ["5", "5", "4", "6", "5", "5", "4", "6", "5", "45"], y: 0.8)
        let r = ScorecardParser.parse(pages: [tokens])
        XCTAssertEqual(r.par, [4, 4, 3, 5, 4, 4, 3, 5, 4])
        XCTAssertEqual(r.players.first?.strokes, [5, 5, 4, 6, 5, 5, 4, 6, 5])
        XCTAssertEqual(r.strokeIndex, [])
    }

    func testNumbers() {
        XCTAssertEqual(ScorecardParser.parseNumber("5"), 5)
        XCTAssertEqual(ScorecardParser.parseNumber("S"), 5)
        XCTAssertEqual(ScorecardParser.parseNumber("4."), 4)
        XCTAssertNil(ScorecardParser.parseNumber("In"))
        XCTAssertNil(ScorecardParser.parseNumber("Out"))
        XCTAssertNil(ScorecardParser.parseNumber("A"))
    }
}

#if canImport(AppKit)
final class ReaderTests: XCTestCase {
    /// Zeichnet eine gedruckte 9-Loch-Karte und liest sie mit der echten Texterkennung.
    func testReadsRenderedCard() throws {
        let w = 1600, h = 700
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.systemFont(ofSize: 40, weight: .medium)
        func text(_ s: String, _ x: Int, _ y: Int) {
            NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.black]).draw(at: NSPoint(x: x, y: y))
        }
        let rows: [(String, [String])] = [
            ("Loch", (1...9).map(String.init) + ["Out"]),
            ("Par", ["4", "5", "3", "4", "4", "3", "5", "4", "4", "36"]),
            ("Hcp", ["7", "1", "15", "9", "3", "17", "5", "11", "13", ""]),
            ("Julia", ["5", "6", "4", "", "5", "4", "6", "5", "5", "45"]),
            ("Peter", ["4", "5", "3", "5", "4", "3", "6", "4", "5", "39"])
        ]
        text("Golfclub Am See   12.10.2026", 60, 600)
        for (r, (label, vals)) in rows.enumerated() {
            let y = 480 - r * 90
            text(label, 60, y)
            for (i, v) in vals.enumerated() { text(v, 330 + i * 115, y) }
        }
        NSGraphicsContext.current = nil
        let image = ctx.makeImage()!

        let r = ScorecardParser.parse(pages: [try ScorecardReader.tokens(from: image)])
        XCTAssertEqual(r.date, "2026-10-12")
        XCTAssertEqual(r.course, "Golfclub Am See")
        XCTAssertEqual(r.par, [4, 5, 3, 4, 4, 3, 5, 4, 4])
        XCTAssertEqual(r.strokeIndex, [7, 1, 15, 9, 3, 17, 5, 11, 13])
        XCTAssertEqual(r.players.map(\.name), ["Julia", "Peter"])
        XCTAssertEqual(r.players[0].strokes, [5, 6, 4, 0, 5, 4, 6, 5, 5])
        XCTAssertEqual(r.players[1].strokes, [4, 5, 3, 5, 4, 3, 6, 4, 5])
    }
}
#endif
