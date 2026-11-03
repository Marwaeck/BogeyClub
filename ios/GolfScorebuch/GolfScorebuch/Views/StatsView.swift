import SwiftUI
import SwiftData
import Charts

struct StatsView: View {
    @Query private var players: [Player]
    @Query private var courses: [Course]
    @Query private var rounds: [Round]
    @Environment(AppState.self) private var app
    @State private var selected: UUID?

    var body: some View {
        @Bindable var app = app
        let data = GolfData(players: players, courses: courses, rounds: rounds)
        let st = data.yearStats(app.year, virt: app.virt)
        NavigationStack {
            List {
                Section { FilterBar(years: data.years, year: $app.year, virtual: $app.virt) }
                if st.isEmpty {
                    ContentUnavailableView("Keine Runden", systemImage: "chart.bar", description: Text("Für diesen Zeitraum sind noch keine Runden erfasst."))
                } else {
                    Section {
                        ForEach(st) { s in
                            Button { selected = s.id } label: { StatsRow(s: s, virt: app.virt, selected: (selected ?? st.first?.id) == s.id) }
                                .foregroundStyle(.primary)
                        }
                    } header: { Text("Rangliste nach Ø Stableford") } footer: {
                        Text("Durchschnitte und Bestwerte aus 18-Loch-Runden. Tippe auf einen Spieler für Details.")
                    }
                    Section("Stableford-Verlauf (18 Loch)") {
                        Chart {
                            ForEach(st) { s in
                                ForEach(s.r18) { p in
                                    LineMark(x: .value("Datum", p.date), y: .value("Punkte", app.virt ? p.vpts : p.pts))
                                        .foregroundStyle(by: .value("Spieler", s.player.name))
                                    PointMark(x: .value("Datum", p.date), y: .value("Punkte", app.virt ? p.vpts : p.pts))
                                        .foregroundStyle(by: .value("Spieler", s.player.name))
                                }
                            }
                            RuleMark(y: .value("Handicap gespielt", 36)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.secondary)
                        }
                        .chartYAxisLabel("Punkte")
                        .frame(height: 220)
                    }
                    if let sel = st.first(where: { $0.id == selected }) ?? st.first {
                        PlayerDetailSections(data: data, stats: sel, year: app.year, virt: app.virt)
                    }
                }
            }
            .navigationTitle(app.year.seasonTitle)
        }
    }
}

struct StatsRow: View {
    let s: PlayerYearStats
    let virt: Bool
    let selected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.player.name).font(.headline)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.fairway) }
                Spacer()
                Text("\(s.rounds) Runden\(s.nine > 0 ? " (\(s.nine)× 9 L.)" : "")").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                metric(Fmt.one(virt ? s.avgVPts : s.avgPts), "Ø Stbf")
                metric(Fmt.one(s.avgGross), "Ø Brutto")
                metric(Fmt.vs(s.avgVs), "Ø Par")
                metric(s.bestGross.map(String.init) ?? "–", "Beste")
                metric(Fmt.one(s.virtual.hi), "Virt. HCP")
            }
        }
        .padding(.vertical, 2)
    }
    private func metric(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading) {
            Text(v).font(.subheadline.bold().monospacedDigit())
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct PlayerDetailSections: View {
    let data: GolfData
    let stats: PlayerYearStats
    let year: YearFilter
    let virt: Bool
    @State private var laCourse: UUID?

    private static let distOrder: [(String, String, Color)] = [
        ("eagle", "Eagle +", Color(red: 0.06, green: 0.30, blue: 0.18)),
        ("birdie", "Birdie", Color(red: 0.18, green: 0.56, blue: 0.36)),
        ("par", "Par", Color(red: 0.61, green: 0.79, blue: 0.68)),
        ("bogey", "Bogey", Color(red: 0.89, green: 0.76, blue: 0.49)),
        ("double", "Doppelbogey", Color(red: 0.88, green: 0.53, blue: 0.31)),
        ("triple", "Triple +", Color(red: 0.72, green: 0.23, blue: 0.18)),
        ("strich", "Strich", Color(.systemGray3))
    ]

    var body: some View {
        let p = stats.player
        let a = data.analysis(p.id, year)
        Section("\(p.name) · \(year.label)") {
            KPIGrid(items: [
                ("\(stats.rounds)", "Runden"),
                (Fmt.one(p.hcp), "Offizielles HCP"),
                (Fmt.one(stats.virtual.hi), stats.virtual.hi == nil ? "Virtuelles HCP (\(stats.virtual.count)/3)" : "Virtuelles HCP"),
                (Fmt.one(stats.avgPts), "Ø Stableford"),
                (Fmt.one(stats.avgVPts), "Ø Stbf virtuell"),
                (stats.bestPts.map(String.init) ?? "–", "Beste Stableford"),
                (Fmt.one(stats.avgGross), "Ø Brutto"),
                (stats.bestGross.map(String.init) ?? "–", "Beste Brutto"),
                (Fmt.vs(stats.avgVs), "Ø über Par"),
                (Fmt.one(virt ? stats.avgVNet : stats.avgNet), "Ø Netto")
            ])
        }
        Section("Badges") { BadgeGrid(data: data, pid: p.id) }
        distribution(a)
        frontBack(a)
        holeAnalysis(a)
        hiSection(p)
        Section("Runden") {
            ForEach(stats.points.reversed()) { pt in
                HStack {
                    VStack(alignment: .leading) {
                        Text(pt.course).lineLimit(1)
                        Text(Fmt.day(pt.day)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("\(virt ? pt.vpts : pt.pts) P.").bold().monospacedDigit()
                        Text(pt.gross.map { "\($0) (\(Fmt.vs(pt.vsPar)))" } ?? (pt.n == 9 ? "9 Loch" : "mit Strichen")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder private func distribution(_ a: Analysis) -> some View {
        let total = a.dist.values.reduce(0, +)
        if total > 0 {
            Section("Score-Verteilung · \(total) Löcher") {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ForEach(Self.distOrder, id: \.0) { k, _, color in
                            let v = a.dist[k] ?? 0
                            if v > 0 { Rectangle().fill(color).frame(width: geo.size.width * CGFloat(v) / CGFloat(total)) }
                        }
                    }
                }
                .frame(height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Self.distOrder.filter { (a.dist[$0.0] ?? 0) > 0 || ["birdie", "par", "bogey", "double"].contains($0.0) }, id: \.0) { k, label, color in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                            Text(label).font(.caption)
                            Text("\(Int((Double(a.dist[k] ?? 0) / Double(total) * 100).rounded())) %").font(.caption.bold()).monospacedDigit()
                        }
                    }
                }
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow { Text("Lochtyp").gridColumnAlignment(.leading); Text("Löcher"); Text("Ø Schläge"); Text("Ø ± Par"); Text("Ø Punkte") }
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach([3, 4, 5], id: \.self) { k in
                        if let x = a.byPar[k], !x.isEmpty {
                            let d = x.map { Double($0.d) }.average ?? 0
                            GridRow {
                                Text("Par \(k)").gridColumnAlignment(.leading)
                                Text("\(x.count)")
                                Text(Fmt.one(Double(k) + d)).bold()
                                Text(Fmt.vs(d))
                                Text(Fmt.one(x.map { Double($0.p) }.average))
                            }
                            .font(.subheadline.monospacedDigit())
                        }
                    }
                }
                if let worst = [3, 4, 5].compactMap({ k -> (Int, Double)? in
                    guard let x = a.byPar[k], !x.isEmpty else { return nil }
                    return (k, x.map { Double($0.d) }.average ?? 0)
                }).max(by: { $0.1 < $1.1 }) {
                    Text("Die meisten Schläge über Par verlierst du auf den Par-\(worst.0)-Löchern (Ø \(Fmt.vs(worst.1))).").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func frontBack(_ a: Analysis) -> some View {
        if !a.fb.isEmpty {
            let f = a.fb.map { Double($0.f) }.average ?? 0, b = a.fb.map { Double($0.b) }.average ?? 0
            let worse = a.fb.filter { $0.b > $0.f }.count
            Section("Front 9 vs. Back 9 · \(a.fb.count) Runden") {
                KPIGrid(items: [
                    (Fmt.vs(f), "Ø vorne über Par"),
                    (Fmt.vs(b), "Ø hinten über Par"),
                    ("\(Fmt.one(a.fb.map { Double($0.fp) }.average)) / \(Fmt.one(a.fb.map { Double($0.bp) }.average))", "Ø Punkte vorne / hinten"),
                    ("\(worse) von \(a.fb.count)", "Runden hinten schwächer")
                ])
                Text(abs(b - f) < 0.75 ? "Vorne und hinten spielst du etwa gleich stark." :
                        b > f ? "Hinten verlierst du im Schnitt \(Fmt.one(b - f)) Schläge mehr als vorne." :
                        "Hinten spielst du im Schnitt \(Fmt.one(f - b)) Schläge besser als vorne.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func holeAnalysis(_ a: Analysis) -> some View {
        let list = a.courses.values.sorted { $0.rounds > $1.rounds }
        if !list.isEmpty {
            let ch = list.first { $0.course.id == laCourse } ?? list[0]
            let c = ch.course, rk = Golf.ranks(c.si, c.holes)
            let pts = (0..<c.holes).map { ch.p[$0].map(Double.init).average ?? 0 }
            let allP = pts.average ?? 0
            let byP = pts.indices.sorted { pts[$0] < pts[$1] }
            let bad = Set(byP.prefix(3).filter { pts[$0] < allP })
            let better = Set(pts.indices.filter { rk[$0] <= Int(ceil(Double(c.holes) / 3)) && pts[$0] >= allP + 0.25 })
            Section {
                Picker("Platz", selection: Binding(get: { ch.course.id }, set: { laCourse = $0 })) {
                    ForEach(list, id: \.course.id) { x in Text("\(x.course.name) (\(x.rounds)×)").tag(x.course.id) }
                }
                Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow { Text("Loch").gridColumnAlignment(.leading); Text("Par"); Text("Vg"); Text("Ø Schl."); Text("± Par"); Text("Ø P.") }
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    ForEach(0..<c.holes, id: \.self) { i in
                        let s = ch.s[i].map(Double.init).average
                        GridRow {
                            HStack(spacing: 4) {
                                Text("\(i + 1)").bold()
                                if bad.contains(i) { Tag(text: "Angst", color: .red) }
                                if better.contains(i) { Tag(text: "Stärke", color: .fairway) }
                            }
                            .gridColumnAlignment(.leading)
                            Text("\(c.pars[i])")
                            Text("\(rk[i])").foregroundStyle(.secondary)
                            Text(Fmt.one(s))
                            Text(s.map { Fmt.vs($0 - Double(c.pars[i])) } ?? "–")
                            Text(Fmt.one(pts[i])).bold()
                        }
                        .font(.subheadline.monospacedDigit())
                    }
                }
            } header: { Text("Loch-Analyse") } footer: {
                Text("Ø \(Fmt.one(allP)) Punkte pro Loch auf diesem Platz. Angst: deine drei punktschwächsten Löcher. Stärke: schweres Loch (Vorgabe im oberen Drittel), auf dem du überdurchschnittlich punktest.")
            }
        }
    }

    @ViewBuilder private func hiSection(_ p: PlayerV) -> some View {
        let tl = data.hiTimeline(p.id, year)
        Section("Handicap-Verlauf · \(year.label)") {
            if tl.isEmpty {
                Text("Das virtuelle Handicap entsteht ab 3 auswertbaren Runden. Bisher: \(data.virtualHI(p.id).count).").font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(tl) { x in
                        LineMark(x: .value("Datum", x.date), y: .value("HCP", x.hi)).foregroundStyle(Color.fairway)
                        PointMark(x: .value("Datum", x.date), y: .value("HCP", x.hi)).foregroundStyle(Color.fairway)
                    }
                    RuleMark(y: .value("Offiziell", p.hcp)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) { Text("offiziell \(Fmt.one(p.hcp))").font(.caption2).foregroundStyle(.secondary) }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                if let last = tl.last { Text("Aktuell: \(Fmt.one(last.hi))").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
}

struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.18))).foregroundStyle(color)
    }
}
