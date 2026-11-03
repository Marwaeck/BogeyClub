import SwiftUI
import SwiftData

struct ReviewView: View {
    @Query private var players: [Player]
    @Query private var courses: [Course]
    @Query private var rounds: [Round]
    @State private var year: YearFilter?
    @State private var pdfURL: URL?
    @State private var pdfError: String?

    var body: some View {
        let data = GolfData(players: players, courses: courses, rounds: rounds)
        let y = year ?? data.years.first.map { YearFilter.year($0) } ?? .all
        let s = data.season(y)
        List {
            Section {
                Picker("Jahr", selection: Binding(get: { y }, set: { year = $0; pdfURL = nil })) {
                    Text("Alle Jahre").tag(YearFilter.all)
                    ForEach(data.years, id: \.self) { Text(String($0)).tag(YearFilter.year($0)) }
                }
                Button { makePDF(s, data) } label: { Label("Als PDF erstellen (A4)", systemImage: "doc.richtext") }
                if let pdfURL { ShareLink("PDF teilen oder sichern", item: pdfURL) }
                if let pdfError { Text(pdfError).foregroundStyle(.red).font(.footnote) }
            }
            if s.rounds.isEmpty {
                ContentUnavailableView("Keine Runden", systemImage: "calendar", description: Text("Für diesen Zeitraum gibt es noch keine Runden."))
            } else {
                Section("Highlights") {
                    KPIGrid(items: [
                        ("\(s.rounds.count)", "Runden"),
                        ("\(s.courses)", "Plätze"),
                        (s.bestG.map { "\($0.value)" } ?? "–", "Beste Bruttorunde\(s.bestG.map { " · \(data.name($0.pid))" } ?? "")"),
                        (s.bestP.map { "\($0.value)" } ?? "–", "Meiste Punkte\(s.bestP.map { " · \(data.name($0.pid))" } ?? "")"),
                        ("\(s.birdies)", "Birdies"),
                        ("\(s.devils)", "666-Momente")
                    ])
                    if let g = s.bestG, let p = s.bestP {
                        Text("Beste Runde: \(g.value) Schläge, \(g.course), \(Fmt.day(g.day)). Meiste Punkte: \(p.value), \(p.course), \(Fmt.day(p.day)).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(s.players) { p in
                    Section(p.name) {
                        KPIGrid(items: [
                            ("\(p.rounds)", "Runden"),
                            (Fmt.one(p.avgPts), "Ø Stableford (18 L.)"),
                            (p.bestPts.map { "\($0.value)" } ?? "–", "Beste Stableford"),
                            (Fmt.one(p.avgGross), "Ø Brutto"),
                            (p.bestGross.map { "\($0.value)" } ?? "–", "Beste Brutto")
                        ])
                        Text(progress(p)).font(.footnote)
                        if let b = p.bestGross { Text("Bestrunde: \(b.value) auf \(b.course) am \(Fmt.day(b.day))").font(.footnote).foregroundStyle(.secondary) }
                        if p.earned.isEmpty {
                            Text("Keine Badges in diesem Zeitraum").font(.footnote).foregroundStyle(.secondary)
                        } else {
                            FlowChips(items: p.earned.map { ("\($0.badge.label)\($0.count > 1 ? " ×\($0.count)" : "")\($0.isNew ? " · neu" : "")", $0.badge.neg) })
                        }
                    }
                }
                if !s.merit.rows.isEmpty { MeritSections(data: data, rows: s.merit.rows, h2h: s.merit.h2h, virt: false) }
            }
        }
        .navigationTitle("Rückblick \(y.label)")
    }

    private func progress(_ p: SeasonPlayer) -> String {
        var parts: [String] = []
        if let a = p.hiStart, let b = p.hiEnd { parts.append("Virtuelles HCP \(Fmt.one(a)) → \(Fmt.one(b)) (\(b < a ? "besser" : b > a ? "schlechter" : "gleich"))") }
        else if let b = p.hiEnd { parts.append("Virtuelles HCP \(Fmt.one(b))") }
        if let f = p.firstHalf, let s = p.secondHalf { parts.append("Stableford 1. Hälfte Ø \(Fmt.one(f)) → 2. Hälfte Ø \(Fmt.one(s))") }
        return parts.isEmpty ? "Noch zu wenige Runden für einen Trend" : "Fortschritt: " + parts.joined(separator: " · ")
    }

    private func makePDF(_ s: Season, _ data: GolfData) {
        let pdf = SeasonPDF.make(s, data: data)
        let name: String
        switch s.filter { case .all: name = "Bogey-Club-Rueckblick-alle-Jahre.pdf"; case .year(let v): name = "Bogey-Club-Rueckblick-\(v).pdf" }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do { try pdf.write(to: url); pdfURL = url; pdfError = nil }
        catch { pdfError = "Das PDF konnte nicht erstellt werden: \(error.localizedDescription)" }
    }
}

struct FlowChips: View {
    let items: [(String, Bool)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { i in
                Text(items[i].0).font(.caption.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().stroke(items[i].1 ? Color.tier(.neg) : Color(.separator)))
                    .foregroundStyle(items[i].1 ? Color.tier(.neg) : .primary)
            }
        }
    }
}
