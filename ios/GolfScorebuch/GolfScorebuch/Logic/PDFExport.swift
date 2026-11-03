import UIKit

/// Einfacher A4-PDF-Schreiber mit Überschriften und Tabellen
final class PDFWriter {
    let page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)   // A4 in Punkt
    let margin: CGFloat = 45
    private var ctx: UIGraphicsPDFRendererContext!
    private var y: CGFloat = 0
    private var pageNo = 0
    private let footer: String

    static let green = UIColor(red: 28 / 255, green: 102 / 255, blue: 65 / 255, alpha: 1)
    static let ink = UIColor(red: 20 / 255, green: 32 / 255, blue: 25 / 255, alpha: 1)
    static let muted = UIColor(red: 88 / 255, green: 103 / 255, blue: 94 / 255, alpha: 1)
    static let stripe = UIColor(red: 238 / 255, green: 243 / 255, blue: 239 / 255, alpha: 1)
    static let line = UIColor(red: 211 / 255, green: 221 / 255, blue: 213 / 255, alpha: 1)

    init(footer: String) { self.footer = footer }

    var width: CGFloat { page.width - 2 * margin }

    func render(_ build: (PDFWriter) -> Void) -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        return renderer.pdfData { c in
            ctx = c
            newPage()
            build(self)
        }
    }

    private func newPage() {
        ctx.beginPage()
        pageNo += 1
        y = margin
        let f = NSAttributedString(string: "\(footer) · Seite \(pageNo)", attributes: [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: Self.muted])
        f.draw(at: CGPoint(x: margin, y: page.height - 28))
    }

    private func ensure(_ h: CGFloat) { if y + h > page.height - margin - 14 { newPage() } }

    @discardableResult
    private func draw(_ s: String, font: UIFont, color: UIColor, x: CGFloat, w: CGFloat, at top: CGFloat, measureOnly: Bool = false) -> CGFloat {
        let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
        let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
        let r = a.boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        if !measureOnly { a.draw(with: CGRect(x: x, y: top, width: w, height: ceil(r.height)), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil) }
        return ceil(r.height)
    }

    func banner(title: String, subtitle: String) {
        Self.green.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: page.width, height: 92))
        draw(title, font: .boldSystemFont(ofSize: 22), color: .white, x: margin, w: width, at: 28)
        draw(subtitle, font: .systemFont(ofSize: 10), color: .white, x: margin, w: width, at: 60)
        y = 120
    }

    func heading(_ s: String) {
        ensure(60)
        let h = draw(s, font: .boldSystemFont(ofSize: 14), color: Self.green, x: margin, w: width, at: y)
        y += h + 6
    }

    /// Tabelle; `widths` sind Anteile der Seitenbreite (Summe 1)
    func table(_ head: [String], _ rows: [[String]], widths: [CGFloat]? = nil, boldFirst: Bool = false) {
        let cols = head.count
        let ws = (widths ?? Array(repeating: 1 / CGFloat(cols), count: cols)).map { $0 * width }
        let pad: CGFloat = 5
        func rowHeight(_ cells: [String], _ font: UIFont) -> CGFloat {
            cells.enumerated().map { i, s in draw(s, font: font, color: Self.ink, x: 0, w: ws[i] - 2 * pad, at: 0, measureOnly: true) }.max()! + 2 * pad
        }
        func drawRow(_ cells: [String], header: Bool, stripe: Bool) {
            let font: UIFont = header ? .boldSystemFont(ofSize: 9) : .systemFont(ofSize: 9)
            let h = rowHeight(cells, font)
            ensure(h)
            let rect = CGRect(x: margin, y: y, width: width, height: h)
            if header { Self.green.setFill(); UIRectFill(rect) } else if stripe { Self.stripe.setFill(); UIRectFill(rect) }
            var x = margin
            for (i, s) in cells.enumerated() {
                let f: UIFont = (!header && boldFirst && i == 0) ? .boldSystemFont(ofSize: 9) : font
                draw(s, font: f, color: header ? .white : Self.ink, x: x + pad, w: ws[i] - 2 * pad, at: y + pad)
                x += ws[i]
            }
            Self.line.setStroke()
            let path = UIBezierPath(); path.move(to: CGPoint(x: margin, y: y + h)); path.addLine(to: CGPoint(x: margin + width, y: y + h)); path.lineWidth = 0.4; path.stroke()
            y += h
        }
        drawRow(head, header: true, stripe: false)
        for (i, r) in rows.enumerated() { drawRow(r.count == cols ? r : r + Array(repeating: "", count: max(0, cols - r.count)), header: false, stripe: i % 2 == 1) }
        y += 16
    }
}

enum SeasonPDF {
    static func make(_ s: Season, data: GolfData) -> Data {
        let label = s.filter.seasonTitle
        let w = PDFWriter(footer: "Bogey Club · \(label)")
        return w.render { pdf in
            pdf.banner(title: "Bogey Club – \(label)",
                       subtitle: "Saisonrückblick · \(s.rounds.count) Runden · \(s.courses) Plätze · \(s.players.count) Spieler · erstellt \(Fmt.date(.now))")
            pdf.heading("Highlights")
            pdf.table(["Kennzahl", "Wert"], [
                ["Runden / Plätze", "\(s.rounds.count) / \(s.courses)"],
                ["Beste Bruttorunde", s.bestG.map { "\($0.value) – \(data.name($0.pid)), \($0.course), \(Fmt.day($0.day))" } ?? "–"],
                ["Meiste Stableford-Punkte", s.bestP.map { "\($0.value) – \(data.name($0.pid)), \($0.course), \(Fmt.day($0.day))" } ?? "–"],
                ["Birdies gesamt", "\(s.birdies)"],
                ["666-Momente (3× Doppelbogey in Folge)", "\(s.devils)"]
            ], widths: [0.38, 0.62], boldFirst: true)
            pdf.heading("Spielerübersicht")
            pdf.table(["Spieler", "Runden", "Ø Stbf", "Beste Stbf", "Ø Brutto", "Beste Brutto", "Virt. HCP"], s.players.map { p in
                [p.name, "\(p.rounds)", Fmt.one(p.avgPts), p.bestPts.map { "\($0.value)" } ?? "–", Fmt.one(p.avgGross), p.bestGross.map { "\($0.value)" } ?? "–",
                 p.hiStart != nil && p.hiEnd != nil ? "\(Fmt.one(p.hiStart)) → \(Fmt.one(p.hiEnd))" : Fmt.one(p.hiEnd)]
            }, widths: [0.2, 0.1, 0.11, 0.13, 0.13, 0.15, 0.18], boldFirst: true)
            pdf.heading("Fortschritt")
            pdf.table(["Spieler", "Trend"], s.players.map { p in
                [p.name, [
                    p.hiStart != nil && p.hiEnd != nil ? "Virtuelles HCP \(Fmt.one(p.hiStart)) → \(Fmt.one(p.hiEnd))" : nil,
                    p.firstHalf != nil ? "Stableford Ø \(Fmt.one(p.firstHalf)) (1. Hälfte) → \(Fmt.one(p.secondHalf)) (2. Hälfte)" : nil,
                    p.bestGross.map { "Bestrunde \($0.value) auf \($0.course) (\(Fmt.day($0.day)))" }
                ].compactMap { $0 }.joined(separator: "\n").nilIfEmpty ?? "Zu wenige Runden für einen Trend"]
            }, widths: [0.22, 0.78], boldFirst: true)
            if !s.merit.rows.isEmpty {
                pdf.heading("Order of Merit")
                pdf.table(["Platz", "Spieler", "Runden", "Rundensiege", "Duellpunkte", "Ø Platz"], s.merit.rows.enumerated().map { i, r in
                    ["\(i + 1).", data.name(r.pid), "\(r.rounds)", "\(r.wins)", Fmt.half(r.duel), Fmt.one(r.avgPlace)]
                }, widths: [0.1, 0.3, 0.13, 0.16, 0.16, 0.15])
                let ps = s.merit.rows.map(\.pid)
                pdf.heading("Duell-Bilanz (Siege : Niederlagen, Zeile gegen Spalte)")
                pdf.table([""] + ps.map { data.name($0) }, ps.map { a in
                    [data.name(a)] + ps.map { b in
                        if a == b { return "–" }
                        guard let x = s.merit.h2h["\(a)|\(b)"] else { return "nie" }
                        return "\(x.w) : \(x.l)" + (x.t > 0 ? " (\(x.t) U)" : "")
                    }
                }, boldFirst: true)
            }
            pdf.heading("Badges")
            pdf.table(["Spieler", "Badges"], s.players.map { p in
                [p.name, p.earned.isEmpty ? "–" : p.earned.map { "\($0.badge.label)\($0.count > 1 ? " ×\($0.count)" : "")\($0.isNew ? " (neu)" : "")" }.joined(separator: ", ")]
            }, widths: [0.22, 0.78], boldFirst: true)
            pdf.heading("Alle Runden")
            pdf.table(["Datum", "Platz", "Ergebnisse (Brutto / Stableford)"], s.rounds.map { r in
                let c = data.course(r.courseID)!
                return [Fmt.day(r.day), c.name, r.entries.filter { data.player($0.playerID) != nil }.map { e in
                    let res = Golf.result(e, c)
                    return "\(data.name(e.playerID)) \(res.gross)\(res.complete ? "" : "*") / \(res.pts)"
                }.joined(separator: "\n")]
            }, widths: [0.16, 0.4, 0.44])
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
