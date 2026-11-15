import Foundation
import CoreGraphics

/// Ein erkanntes Wort mit Position (normiert 0…1, Ursprung unten links wie bei Apple Vision).
public struct OCRToken: Hashable {
    public var text: String
    public var box: CGRect
    public init(_ text: String, _ box: CGRect) { self.text = text; self.box = box }
}

/// Ergebnis im selben Format, das die Web-App von der Claude-Erkennung erwartet.
public struct ScanResult: Equatable {
    public struct Player: Equatable { public var name: String; public var strokes: [Int] }
    public var course: String?
    public var date: String?
    public var par: [Int]
    public var strokeIndex: [Int]
    public var players: [Player]

    public var jsonObject: [String: Any] {
        [
            "course": course as Any? ?? NSNull(),
            "date": date as Any? ?? NSNull(),
            "par": par,
            "strokeIndex": strokeIndex,
            "players": players.map { ["name": $0.name, "strokes": $0.strokes] }
        ]
    }
}

/// Baut aus erkannten Wörtern eine Scorekarte: Zeilen bilden, Lochnummern-Zeile als Spaltenraster
/// nutzen (so werden leere Felder zu 0 und Summenspalten fallen weg), dann Par, Lochvorgaben und
/// Spielerzeilen erkennen. Mehrere Bilder bzw. Kartenhälften (Loch 1–9 und 10–18) werden zusammengeführt.
public enum ScorecardParser {

    struct Cell { var text: String; var value: Int?; var x: CGFloat }
    struct Line { var cells: [Cell]; var y: CGFloat; var height: CGFloat
        var label: String { cells.filter { $0.value == nil }.map(\.text).joined(separator: " ") }
        var numbers: [Cell] { cells.filter { $0.value != nil } }
    }
    /// Ein Kartenblock: Zeilen unter einer Lochnummern-Zeile, mit Loch-Offset und Spaltenraster.
    struct Section { var offset: Int; var columns: [CGFloat]?; var spacing: CGFloat; var lines: [Line]; var holeCount: Int }

    public static func parse(pages: [[OCRToken]]) -> ScanResult {
        var par: [Int: Int] = [:], si: [Int: Int] = [:]
        var players: [(key: String, name: String, strokes: [Int: Int])] = []
        var holeCount = 0, maxPlayerCount = 0
        var course: String?, date: String?

        for tokens in pages {
            let lines = buildLines(tokens)
            if date == nil { date = findDate(tokens.map(\.text)) }
            if course == nil { course = findCourse(lines) }

            for section in sections(lines) {
                holeCount = max(holeCount, section.holeCount)
                for line in section.lines {
                    let kind = classify(line)
                    if kind == .skip { continue }
                    let values = align(line, columns: section.columns, kind: kind)
                    guard values.filter({ $0 > 0 }).count >= 3 else { continue }
                    let o = section.offset
                    switch kind {
                    case .par:
                        for (i, v) in values.enumerated() where v > 0 { par[o + i] = v }
                    case .strokeIndex:
                        for (i, v) in values.enumerated() where v > 0 { si[o + i] = v }
                    case .player(let name):
                        maxPlayerCount = max(maxPlayerCount, o + values.count)
                        let key = playerKey(name)
                        var idx = players.firstIndex { $0.key == key && !key.isEmpty }
                        if idx == nil { players.append((key, name, [:])); idx = players.count - 1 }
                        for (i, v) in values.enumerated() where players[idx!].strokes[o + i] == nil || v > 0 {
                            players[idx!].strokes[o + i] = v
                        }
                    case .skip: break
                    }
                }
            }
        }

        // Lochzahl: aus Lochnummern, sonst aus Par, sonst aus der längsten Spielerzeile
        let parCount = (par.keys.max() ?? -1) + 1
        let longest = max(holeCount, parCount, maxPlayerCount)
        let n = longest >= 14 ? 18 : 9
        let list = { (m: [Int: Int]) in (0..<n).map { m[$0] ?? 0 } }

        var parList = list(par)
        if parList.filter({ (3...6).contains($0) }).count < n - 2 { parList = [] }
        var siList = list(si)
        if Set(siList.filter { $0 > 0 }).count < n - 2 { siList = [] }

        let result = players.enumerated().map { i, p -> ScanResult.Player in
            ScanResult.Player(name: p.name.isEmpty ? "Spieler \(i + 1)" : p.name, strokes: list(p.strokes))
        }.filter { $0.strokes.contains { $0 > 0 } }
        return ScanResult(course: course, date: date, par: parList, strokeIndex: siList, players: result)
    }

    /// Eine leere Zelle: Mitte (normiert), Spaltenabstand und Zeilenhöhe.
    public struct MissingCell { public var center: CGPoint; public var spacing: CGFloat; public var height: CGFloat }

    /// Leere Zellen in Par-, Vorgabe-, Spieler- und Lochnummern-Zeilen. Die Texterkennung übersieht
    /// einzeln stehende Ziffern gern; dort wird gezielt noch einmal gelesen.
    public static func missingCells(_ tokens: [OCRToken]) -> [MissingCell] {
        var out: [MissingCell] = []
        for section in sections(buildLines(tokens)) {
            guard let cols = section.columns else { continue }
            for line in section.lines {
                let kind = classify(line)
                guard kind != .skip || isHoleLabel(line) else { continue }
                for x in cols where !line.numbers.contains(where: { abs($0.x - x) < section.spacing * 0.5 }) {
                    out.append(MissingCell(center: CGPoint(x: x, y: line.y), spacing: section.spacing, height: line.height))
                }
            }
        }
        return out
    }

    /// Zerlegt die Zeilen in Blöcke. Ein Block beginnt mit einer Lochnummern-Zeile (vollständig erkannt
    /// oder mit „Loch“/„Hole“ beschriftet). Spaltenraster: Lochnummern, sonst aus den Zahlenpositionen geschätzt.
    static func sections(_ lines: [Line]) -> [Section] {
        var result: [Section] = []
        var current = Section(offset: 0, columns: nil, spacing: 0, lines: [], holeCount: 0)
        func finish() {
            if current.columns == nil, let (cols, sp) = clusterColumns(current.lines) { current.columns = cols; current.spacing = sp }
            if current.columns != nil || !current.lines.isEmpty { result.append(current) }
        }
        for line in lines {
            if let run = holeRun(line) {
                finish()
                let sp = zip(run.xs.dropFirst(), run.xs).map { $0 - $1 }.sorted()[(run.xs.count - 1) / 2]
                current = Section(offset: run.first - 1, columns: run.xs, spacing: sp, lines: [], holeCount: run.first - 1 + run.xs.count)
            } else if isHoleLabel(line) {
                finish()
                let lowest = line.numbers.compactMap(\.value).filter { (1...18).contains($0) }.min() ?? 1
                current = Section(offset: lowest >= 10 ? 9 : 0, columns: nil, spacing: 0, lines: [line], holeCount: 0)
            } else {
                current.lines.append(line)
            }
        }
        finish()
        return result
    }

    static func isHoleLabel(_ line: Line) -> Bool {
        let words = line.label.lowercased().split(whereSeparator: { !$0.isLetter })
        return words.contains { ["loch", "hole", "holes", "bahn", "löcher"].contains($0) }
    }

    /// Spalten aus den x-Positionen der Zahlen aller Zeilen schätzen (wo mehrere Zeilen eine Zahl haben).
    static func clusterColumns(_ lines: [Line]) -> ([CGFloat], CGFloat)? {
        let rows = lines.filter { classify($0) != .skip || isHoleLabel($0) }
            .map { $0.numbers.filter { (1...20).contains($0.value ?? 0) }.map(\.x).sorted() }
            .filter { $0.count >= 3 }
        guard rows.count >= 2 else { return nil }
        let diffs = rows.flatMap { xs in zip(xs.dropFirst(), xs).map { $0 - $1 } }.filter { $0 > 0.005 }.sorted()
        guard !diffs.isEmpty else { return nil }
        let spacing = diffs[diffs.count / 5]
        var clusters: [[CGFloat]] = []
        for x in rows.flatMap({ $0 }).sorted() {
            if let last = clusters.last, let lx = last.last, x - lx < spacing * 0.45 { clusters[clusters.count - 1].append(x) }
            else { clusters.append([x]) }
        }
        let need = max(2, Int((Double(rows.count) * 0.3).rounded()))
        let cols = clusters.filter { $0.count >= need }.map { $0.reduce(0, +) / CGFloat($0.count) }
        return cols.count >= 5 ? (cols, spacing) : nil
    }

    // MARK: Zeilen

    static func buildLines(_ tokens: [OCRToken]) -> [Line] {
        guard !tokens.isEmpty else { return [] }
        let heights = tokens.map(\.box.height).sorted()
        let tolerance = heights[heights.count / 2] * 0.6
        var groups: [[OCRToken]] = []
        for t in tokens.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = groups.last {
                let ref = last.map(\.box.midY).reduce(0, +) / CGFloat(last.count)
                if abs(ref - t.box.midY) < tolerance { groups[groups.count - 1].append(t); continue }
            }
            groups.append([t])
        }
        return groups.map { g in
            let cells = g.sorted { $0.box.minX < $1.box.minX }.map { Cell(text: $0.text, value: parseNumber($0.text), x: $0.box.midX) }
            let hs = g.map(\.box.height).sorted()
            return Line(cells: cells, y: g.map(\.box.midY).reduce(0, +) / CGFloat(g.count), height: hs[hs.count / 2])
        }
    }

    /// Lochnummern-Zeile: aufsteigende Folge 1…9, 10…18 oder 1…18 (Summenspalten wie „Out“ dazwischen sind egal).
    static func holeRun(_ line: Line) -> (first: Int, xs: [CGFloat])? {
        let nums = line.numbers.filter { ($0.value ?? 0) <= 18 }
        var best: [Cell] = [], run: [Cell] = []
        for c in nums {
            if let last = run.last, c.value == (last.value ?? 0) + 1 { run.append(c) } else { run = [c] }
            if run.count > best.count { best = run }
        }
        guard let first = best.first?.value, best.count == 9 || best.count == 18, first == 1 || first == 10 else { return nil }
        return (first, best.map(\.x))
    }

    enum Kind: Equatable { case par, strokeIndex, player(String), skip }

    /// Zeilen, die keine Spieler sind: ganze Wörter (Farben der Abschläge) bzw. Wortanfänge.
    static let skipExact: Set<String> = ["loch", "hole", "holes", "bahn", "löcher", "rot", "gelb", "blau", "weiß", "weiss", "schwarz", "orange", "tee", "gir", "cr", "date"]
    static let skipPrefix = ["meter", "yard", "länge", "laenge", "punkte", "stableford", "netto", "brutto", "putt",
                             "fairway", "green", "datum", "total", "summe", "gesamt", "marker", "zähler", "unterschrift",
                             "signature", "slope", "abschlag", "vorgabeschl", "score", "ergebnis"]

    static func classify(_ line: Line) -> Kind {
        let label = line.label.trimmingCharacters(in: .whitespaces)
        let lower = label.lowercased()
        let words = lower.split(whereSeparator: { !$0.isLetter }).map(String.init)
        let small = line.numbers.compactMap(\.value).filter { (1...20).contains($0) }
        let big = line.numbers.compactMap(\.value).filter { $0 > 20 }
        if big.count > small.count { return .skip }                         // Längen
        if words.contains("par") { return .par }
        if words.contains(where: { ["hcp", "hdcp", "si", "index", "hc", "vorgabe", "handicap", "stroke", "lochvorgabe"].contains($0) }) {
            return .strokeIndex
        }
        if words.contains(where: { w in skipExact.contains(w) || skipPrefix.contains { w.hasPrefix($0) } }) { return .skip }
        // Ohne Beschriftung: Par (lauter 3–5) oder Lochvorgaben (verschiedene Werte bis 18)
        if label.isEmpty {
            if small.count >= 9, small.allSatisfy({ (3...5).contains($0) }) { return .par }
            if small.count >= 9, Set(small).count == small.count, small.contains(1) { return .strokeIndex }
            return small.count >= 5 ? .player("") : .skip
        }
        guard words.contains(where: { $0.count >= 2 }), small.count >= 5 else { return .skip }
        return .player(cleanName(label))
    }

    /// Werte einer Zeile in Lochreihenfolge. Mit Spaltenraster: nächstgelegenes Wort je Loch, leer = 0.
    static func align(_ line: Line, columns: [CGFloat]?, kind: Kind) -> [Int] {
        let maxValue = kind == .strokeIndex ? 18 : (kind == .par ? 6 : 15)
        let nums = line.numbers.filter { (1...maxValue).contains($0.value ?? 0) }
        guard let cols = columns, cols.count >= 2 else { return nums.compactMap(\.value) }
        let spacing = zip(cols.dropFirst(), cols).map { $0 - $1 }.sorted()[(cols.count - 1) / 2]
        var out = Array(repeating: 0, count: cols.count)
        var used = Set<Int>()
        for (j, x) in cols.enumerated() {
            var best: (Int, CGFloat)? = nil
            for (k, c) in nums.enumerated() where !used.contains(k) {
                let d = abs(c.x - x)
                if d < spacing * 0.5, d < (best?.1 ?? .infinity) { best = (k, d) }
            }
            if let (k, _) = best { used.insert(k); out[j] = nums[k].value ?? 0 }
        }
        return out
    }

    // MARK: Hilfen

    static func cleanName(_ s: String) -> String {
        let parts = s.split(separator: " ").filter { w in
            !w.contains(where: \.isNumber) && w.contains(where: \.isLetter)
        }
        return parts.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,:;-–_()[]"))
    }

    static func playerKey(_ name: String) -> String {
        name.lowercased().split(separator: " ").first.map(String.init) ?? ""
    }

    static func findDate(_ texts: [String]) -> String? {
        let joined = texts.joined(separator: " ")
        if let m = joined.range(of: #"\b(20\d\d)-(\d\d)-(\d\d)\b"#, options: .regularExpression) {
            return String(joined[m])
        }
        let pattern = try! NSRegularExpression(pattern: #"\b(\d{1,2})[./](\d{1,2})[./](\d{2}|\d{4})\b"#)
        let ns = joined as NSString
        for m in pattern.matches(in: joined, range: NSRange(location: 0, length: ns.length)) {
            let d = Int(ns.substring(with: m.range(at: 1)))!, mo = Int(ns.substring(with: m.range(at: 2)))!
            var y = Int(ns.substring(with: m.range(at: 3)))!
            if y < 100 { y += 2000 }
            if (1...31).contains(d), (1...12).contains(mo), (2000...2100).contains(y) {
                return String(format: "%04d-%02d-%02d", y, mo, d)
            }
        }
        return nil
    }

    static func findCourse(_ lines: [Line]) -> String? {
        for l in lines where l.numbers.isEmpty {
            let t = l.label.split(separator: " ").filter { !$0.contains(where: \.isNumber) }.joined(separator: " ")
            let lower = t.lowercased()
            if t.count >= 6, t.count <= 60,
               lower.contains("golf") || lower.contains("country") || lower.hasPrefix("gc ") || lower.contains(" gc") || lower.contains("club") {
                return t
            }
        }
        return nil
    }

    /// Zahlen inkl. typischer Verwechslungen bei Handschrift (O→0, l→1, S→5 …), wie in der iOS-App.
    public static func parseNumber(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;-–_()[]*"))
        if let n = Int(trimmed) { return n }
        guard (1...2).contains(trimmed.count) else { return nil }
        let map: [Character: Character] = ["O": "0", "o": "0", "D": "0", "l": "1", "I": "1", "i": "1",
                                           "|": "1", "Z": "2", "z": "2", "S": "5", "s": "5",
                                           "G": "6", "b": "6", "T": "7", "B": "8", "g": "9", "q": "9"]
        // Einzelne Buchstaben nur umdeuten, wenn sie nicht Teil eines Wortes sind („in“, „Out“ bleiben Text)
        if trimmed.count == 2, trimmed.allSatisfy(\.isLetter) { return nil }
        if trimmed.count == 1, !"OolISZsTBgq|".contains(trimmed) { return nil }
        return Int(String(trimmed.map { map[$0] ?? $0 }))
    }
}
