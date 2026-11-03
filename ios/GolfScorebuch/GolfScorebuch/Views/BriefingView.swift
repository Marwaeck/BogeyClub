import SwiftUI
import SwiftData

/// Prognose für alle Spieler und Platz-Briefing pro Spieler
struct BriefingView: View {
    @Query private var players: [Player]
    @Query(sort: \Course.name) private var courses: [Course]
    @Query private var rounds: [Round]
    @State private var courseID: UUID?
    @State private var playerID: UUID?

    var body: some View {
        let data = GolfData(players: players, courses: courses, rounds: rounds)
        NavigationStack {
            List {
                if data.courses.isEmpty {
                    ContentUnavailableView("Noch keine Plätze", systemImage: "map", description: Text("Lege Plätze an oder erfasse Runden, dann siehst du hier deine Prognose."))
                } else {
                    let c = data.course(courseID) ?? data.courses.sorted { $0.name < $1.name }[0]
                    Section {
                        Picker("Platz", selection: Binding(get: { c.id }, set: { courseID = $0 })) {
                            ForEach(data.courses.sorted { $0.name < $1.name }) { Text($0.name).tag($0.id) }
                        }
                        Text("\(c.holes) Loch · Par \(c.par) · CR \(Fmt.one(c.cr)) · Slope \(c.slope)").font(.footnote).foregroundStyle(.secondary)
                    }
                    forecastSection(data, c)
                    if !data.players.isEmpty { briefing(data, c) }
                }
            }
            .navigationTitle("Platz-Briefing")
        }
    }

    @ViewBuilder private func forecastSection(_ data: GolfData, _ c: CourseV) -> some View {
        let rows = data.players.map { ($0, data.forecast($0, c)) }.sorted { ($0.1.none ? 999 : $0.1.exp) < ($1.1.none ? 999 : $1.1.exp) }
        Section {
            ForEach(rows, id: \.0.id) { p, f in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(p.name).font(.headline)
                        if !f.none && f.rounds < 3 { Text("unsicher").font(.caption2).foregroundStyle(.secondary) }
                        Spacer()
                        if !f.none { Text("\(f.exp)").font(.title3.bold()).monospacedDigit(); Text("(\(Fmt.vs(f.vsPar)))").font(.caption).foregroundStyle(.secondary) }
                    }
                    if f.none {
                        Text("Noch keine auswertbare Runde").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Gute Runde \(f.good.map(String.init) ?? "–") · Stbf erwartet \(f.stb) (SV \(f.ph))\(f.vstb.map { " · virtuell \($0) (SV \(f.vph ?? 0))" } ?? "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if f.histCount > 0 {
                        Text("Bisher hier: \(f.histAvgGross.map { "Ø \(Fmt.one($0))" } ?? "–") · \(Fmt.one(f.histAvgPts)) P. · \(f.histCount)×").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: { Text("Prognose") } footer: {
            Text("Erwartet: Course Rating plus Ø der letzten bis zu 10 Score-Differentials, umgerechnet mit dem Slope. Gute Runde: Score auf Höhe des virtuellen Handicaps.")
        }
    }

    @ViewBuilder private func briefing(_ data: GolfData, _ c: CourseV) -> some View {
        let sorted = data.players.sorted { $0.name < $1.name }
        let p = data.player(playerID ?? UUID()) ?? sorted.first { pl in data.rounds.contains { $0.entries.contains { $0.playerID == pl.id } } } ?? sorted[0]
        let n = c.holes, rk = Golf.ranks(c.si, n), ph = Golf.courseHcp(p.hcp, c)
        let v = data.virtualHI(p.id).hi
        let vph = v.map { Golf.courseHcp($0, c) }
        let a = data.analysis(p.id, .all), here = a.courses[c.id], f = data.forecast(p, c)
        let holePts: [Double?] = (0..<n).map { i in here.flatMap { $0.p[i].isEmpty ? nil : $0.p[i].map(Double.init).average } }
        let holeAvg: [Double?] = (0..<n).map { i in here.flatMap { $0.s[i].isEmpty ? nil : $0.s[i].map(Double.init).average } }
        let allP = holePts.compactMap { $0 }.average
        let ranked = holePts.indices.filter { holePts[$0] != nil }.sorted { holePts[$0]! < holePts[$1]! }
        let fear = Set(ranked.prefix(3).filter { allP != nil && holePts[$0]! < allP! })
        let strong = Set(ranked.suffix(3).filter { allP != nil && holePts[$0]! > allP! + 0.25 })
        Section {
            Picker("Spieler", selection: Binding(get: { p.id }, set: { playerID = $0 })) {
                ForEach(sorted) { Text($0.name).tag($0.id) }
            }
            KPIGrid(items: [
                ("\(ph)", "Spielvorgabe (HCP \(Fmt.one(p.hcp)))"),
                (vph.map(String.init) ?? "–", "Spielvorgabe virtuell\(v.map { " (\(Fmt.one($0)))" } ?? "")"),
                (f.none ? "–" : "\(f.exp)", "Erwarteter Score"),
                ("\(c.par + ph)", "Brutto für 36 Punkte")
            ])
            ForEach(tips(data, p, c, a, f, ph, fear: fear, hasHistory: here != nil), id: \.self) { t in
                Label(t, systemImage: "lightbulb").font(.callout)
            }
        } header: { Text("Briefing") }
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow { Text("Loch").gridColumnAlignment(.leading); Text("Par"); Text("Vg"); Text("Vorg."); Text("Ziel 2 P."); Text("Ø hier"); Text("Ø P.") }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(0..<n, id: \.self) { i in
                    let rec = Golf.received(rank: rk[i], ph: ph, n: n), par = c.pars[i]
                    let pa = a.byPar[par].flatMap { $0.isEmpty ? nil : $0.map { Double($0.d) }.average }
                    GridRow {
                        HStack(spacing: 3) {
                            Text("\(i + 1)").bold()
                            if fear.contains(i) { Tag(text: "Angst", color: .red) }
                            if strong.contains(i) { Tag(text: "Stärke", color: .fairway) }
                        }
                        .gridColumnAlignment(.leading)
                        Text("\(par)")
                        Text("\(rk[i])").foregroundStyle(.secondary)
                        Text(rec > 0 ? String(repeating: "•", count: min(rec, 4)) : "\(rec)").foregroundStyle(Color.fairway)
                        Text("\(par + rec)").bold()
                        Text(holeAvg[i].map { Fmt.one($0) } ?? pa.map { "≈\(Fmt.one(Double(par) + $0))" } ?? "–")
                        Text(Fmt.one(holePts[i]))
                    }
                    .font(.subheadline.monospacedDigit())
                }
            }
        } header: { Text("Lochplan für \(p.name)") } footer: {
            Text("Ziel 2 Punkte = Netto-Par: Par plus deine Vorgabeschläge (•). Wer jedes Loch so spielt, kommt auf 36 Punkte. „≈“ heißt geschätzt aus deinem Schnitt auf diesem Par-Typ.")
        }
    }

    private func tips(_ data: GolfData, _ p: PlayerV, _ c: CourseV, _ a: Analysis, _ f: Forecast, _ ph: Int, fear: Set<Int>, hasHistory: Bool) -> [String] {
        var t: [String] = []
        if !f.none { t.append("Erwartet: rund \(f.exp) Schläge (\(Fmt.vs(f.vsPar))), gute Runde \(f.good.map(String.init) ?? "–"). Für 36 Punkte reichen \(c.par + ph) Schläge.") }
        if let worst = [3, 4, 5].compactMap({ k -> (Int, Double)? in
            guard let x = a.byPar[k], !x.isEmpty else { return nil }
            return (k, x.map { Double($0.d) }.average ?? 0)
        }).max(by: { $0.1 < $1.1 }) {
            t.append("Auf Par-\(worst.0)-Löchern verlierst du im Schnitt am meisten (\(Fmt.vs(worst.1))). Hier gibt es \(c.pars.filter { $0 == worst.0 }.count) davon.")
        }
        if a.fb.count >= 3 {
            let fF = a.fb.map { Double($0.f) }.average ?? 0, fB = a.fb.map { Double($0.b) }.average ?? 0
            if fB - fF >= 0.75 { t.append("Hinten spielst du im Schnitt \(Fmt.one(fB - fF)) Schläge schlechter als vorne – auf den letzten Löchern Konzentration halten.") }
            else if fF - fB >= 0.75 { t.append("Vorne verlierst du im Schnitt \(Fmt.one(fF - fB)) Schläge mehr – Aufwärmen lohnt sich.") }
        }
        if !fear.isEmpty { t.append("Angstlöcher hier: \(fear.sorted().map { String($0 + 1) }.joined(separator: ", ")) – lieber auf Netto-Par spielen als auf Risiko.") }
        if !hasHistory { t.append("Auf diesem Platz gibt es noch keine Runde von dir; die Lochwerte stützen sich auf deinen Schnitt je Par-Typ.") }
        return t
    }
}
