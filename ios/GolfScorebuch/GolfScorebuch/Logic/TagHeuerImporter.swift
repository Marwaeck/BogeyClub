import Foundation
import WebKit
import SwiftUI

/// Ergebnis eines Link-Imports: erkannte Zeilen plus Platzangaben
struct LinkImport {
    var rows: [ScannedRow]
    var courseName: String?
    var date: Date?
    var rating: Double?
    var slope: Int?
    var rawText: String
}

/// Lädt eine geteilte TAG-Heuer-Rundenseite in einer WebView (die Seite wird per JavaScript aufgebaut)
/// und liest danach den sichtbaren Text aus.
struct TagHeuerWebView: UIViewRepresentable {
    let url: URL
    var onText: (String, String) -> Void      // (title, innerText)
    var onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.navigationDelegate = context.coordinator
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: TagHeuerWebView
        var done = false
        init(_ p: TagHeuerWebView) { parent = p }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { poll(webView, attempt: 0) }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }

        private func fail(_ error: Error) {
            guard !done else { return }
            done = true
            parent.onError("Die Seite konnte nicht geladen werden: \(error.localizedDescription)")
        }

        /// Wartet, bis die Scorekarte gerendert ist (Zeilen mit vielen Zahlen), höchstens ~12 s
        private func poll(_ web: WKWebView, attempt: Int) {
            guard !done else { return }
            web.evaluateJavaScript("JSON.stringify({t: document.title, x: document.body ? document.body.innerText : ''})") { [weak self] value, _ in
                guard let self, !self.done else { return }
                var title = "", text = ""
                if let s = value as? String, let d = s.data(using: .utf8),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: String] {
                    title = o["t"] ?? ""; text = o["x"] ?? ""
                }
                let ready = LinkParser.numericLines(text) >= 4
                if ready || attempt >= 24 {
                    self.done = true
                    self.parent.onText(title, text)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.poll(web, attempt: attempt + 1) }
                }
            }
        }
    }
}

/// Wandelt den Seitentext in Scorekarten-Zeilen um.
/// Tabellen erscheinen im Text als Zeilen mit Tabulatoren; Front 9 und Back 9 werden zusammengeführt.
enum LinkParser {
    static func numericLines(_ text: String) -> Int {
        text.split(separator: "\n").filter { line in
            line.split(whereSeparator: { $0 == "\t" || $0 == " " }).compactMap { Int($0) }.count >= 5
        }.count
    }

    static func parse(title: String, text: String) -> LinkImport {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var heading = ""          // letzte reine Textzeile (z. B. Spielername)
        var holeCols: [Int: Int] = [:]   // Zellenindex -> Lochnummer
        var holeCellCount = 0
        var rows: [(label: String, holes: [Int: Int])] = []
        let sumWords = ["out", "in", "total", "gesamt", "aus", "ein", "brutto", "netto", "summe"]

        for line in lines {
            let cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            let parts = cells.count > 1 ? cells : line.components(separatedBy: " ").filter { !$0.isEmpty }
            let nums = parts.enumerated().compactMap { i, s -> (Int, Int)? in Int(s).map { (i, $0) } }
            let words = parts.filter { Int($0) == nil && !$0.isEmpty }

            // Kopfzeile mit Lochnummern (1–9 oder 10–18)
            let values = nums.map(\.1)
            if values.count >= 9, isHoleHeader(values) {
                holeCols = Dictionary(uniqueKeysWithValues: nums.filter { (1...18).contains($0.1) }.map { ($0.0, $0.1) })
                holeCellCount = parts.count
                continue
            }
            if nums.count < 5 {
                if nums.isEmpty, line.count <= 40, !sumWords.contains(line.lowercased()) { heading = line }
                continue
            }
            let label = ([heading] + words).filter { !$0.isEmpty }.joined(separator: " · ")
            var holes: [Int: Int] = [:]
            if !holeCols.isEmpty && parts.count == holeCellCount {
                for (col, hole) in holeCols { if col < parts.count, let v = Int(parts[col]) { holes[hole] = v } }
            } else {
                // Ohne passende Kopfzeile: Summen (über 20) weglassen, Reihenfolge = Lochreihenfolge
                let start = holeCols.values.min() ?? 1
                let vals = values.filter { $0 <= 20 }
                for (k, v) in vals.prefix(18).enumerated() { holes[start + k] = v }
            }
            if holes.isEmpty { continue }
            // Gleiche Bezeichnung aus der zweiten Hälfte ergänzt die erste
            if let i = rows.lastIndex(where: { $0.label == label }), Set(rows[i].holes.keys).isDisjoint(with: holes.keys) {
                rows[i].holes.merge(holes) { a, _ in a }
            } else {
                rows.append((label, holes))
            }
        }

        let scanned = rows.map { r -> ScannedRow in
            let maxHole = r.holes.keys.max() ?? 9
            let n = maxHole > 9 ? 18 : 9
            return ScannedRow(label: r.label, numbers: (1...n).map { r.holes[$0] ?? 0 })
        }

        var imp = LinkImport(rows: scanned, rawText: text)
        imp.courseName = courseName(title: title, lines: lines)
        imp.date = findDate(text)
        if let m = text.range(of: #"(\d{2}[.,]\d)\s*/\s*(\d{2,3})"#, options: .regularExpression) {
            let parts = text[m].components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            imp.rating = Double(parts[0].replacingOccurrences(of: ",", with: "."))
            imp.slope = Int(parts[1])
        }
        return imp
    }

    private static func isHoleHeader(_ v: [Int]) -> Bool {
        let holes = v.filter { (1...18).contains($0) }
        guard holes.count >= 9 else { return false }
        let first9 = Array(holes.prefix(9))
        return first9 == Array(1...9) || first9 == Array(10...18)
    }

    private static func courseName(title: String, lines: [String]) -> String? {
        if let l = lines.first(where: { $0.localizedCaseInsensitiveContains("golf") && $0.count <= 80 }) { return l }
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private static func findDate(_ text: String) -> Date? {
        let en = DateFormatter(); en.locale = Locale(identifier: "en_US_POSIX"); en.dateFormat = "MMMM d, yyyy"
        if let r = text.range(of: #"(January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4}"#, options: .regularExpression),
           let d = en.date(from: String(text[r])) { return d }
        let de = DateFormatter(); de.locale = Locale(identifier: "de_DE"); de.dateFormat = "d. MMMM yyyy"
        if let r = text.range(of: #"\d{1,2}\. (Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember) \d{4}"#, options: .regularExpression),
           let d = de.date(from: String(text[r])) { return d }
        let num = DateFormatter(); num.dateFormat = "dd.MM.yyyy"
        if let r = text.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression), let d = num.date(from: String(text[r])) { return d }
        return nil
    }
}

/// Sheet: Link eingeben, Seite laden, Ergebnis zurückgeben
struct LinkImportView: View {
    @Environment(\.dismiss) private var dismiss
    var onResult: (LinkImport) -> Void
    @State private var urlText = ""
    @State private var loadingURL: URL?
    @State private var error: String?
    @State private var lastRaw: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://www.tagheuergolf.com/rounds/…", text: $urlText)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Aus Zwischenablage einfügen") { urlText = UIPasteboard.general.string ?? urlText }
                } header: { Text("Link zur Runde") } footer: {
                    Text("In der TAG-Heuer-Golf-App die Runde teilen und den Link hier einfügen. Die Seite wird geladen und die Werte werden übernommen – danach kannst du alles prüfen.")
                }
                if let loadingURL {
                    Section("Wird geladen …") {
                        TagHeuerWebView(url: loadingURL, onText: { title, text in
                            let imp = LinkParser.parse(title: title, text: text)
                            self.loadingURL = nil
                            if imp.rows.isEmpty {
                                lastRaw = text
                                error = "Auf der Seite wurden keine Scorekarten-Zeilen gefunden."
                            } else {
                                onResult(imp); dismiss()
                            }
                        }, onError: { msg in self.loadingURL = nil; error = msg })
                        .frame(height: 220)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if let lastRaw { ShareLink("Seitentext teilen (zur Fehlersuche)", item: lastRaw) }
                    }
                }
            }
            .navigationTitle("Runde per Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Laden") {
                        error = nil; lastRaw = nil
                        if let u = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme?.hasPrefix("http") == true {
                            loadingURL = u
                        } else { error = "Bitte einen vollständigen Link eingeben." }
                    }
                    .disabled(urlText.isEmpty || loadingURL != nil)
                }
            }
        }
    }
}
