import SwiftUI
import SwiftData

struct RankingView: View {
    @Query private var players: [Player]
    @Query private var courses: [Course]
    @Query private var rounds: [Round]
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        let data = GolfData(players: players, courses: courses, rounds: rounds)
        let m = data.merit(app.year, virt: app.virt)
        NavigationStack {
            List {
                Section { FilterBar(years: data.years, year: $app.year, virtual: $app.virt) }
                if m.rows.isEmpty {
                    ContentUnavailableView("Noch keine gemeinsamen Runden", systemImage: "trophy", description: Text("Sobald eine Runde mit mindestens zwei Spielern gesichert ist, erscheint hier das Ranking."))
                } else {
                    MeritSections(data: data, rows: m.rows, h2h: m.h2h, virt: app.virt)
                }
                Section {
                    ForEach(data.players.sorted { data.earnedCount($0.id) > data.earnedCount($1.id) }) { p in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(p.name).font(.headline)
                                Spacer()
                                Text("\(data.earnedCount(p.id)) von \(BadgeDef.all.filter { !$0.neg }.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            BadgeGrid(data: data, pid: p.id)
                        }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Badges · alle Jahre") } footer: {
                    Text("Unter 110/100/90/80 nur für vollständige 18-Loch-Runden. „666“ ist ein Negativ-Badge und zählt nicht zur Badge-Anzahl.")
                }
            }
            .navigationTitle("Ranking")
        }
    }
}

struct MeritSections: View {
    let data: GolfData
    let rows: [MeritRow]
    let h2h: [String: H2H]
    let virt: Bool

    var body: some View {
        Section {
            Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow { Text("#").gridColumnAlignment(.leading); Text("Spieler").gridColumnAlignment(.leading); Text("Runden"); Text("Siege"); Text("Duelle"); Text("Quote") }
                    .font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(rows.enumerated()), id: \.element.pid) { i, r in
                    GridRow {
                        Text("\(i + 1).").bold()
                        Text(data.name(r.pid)).lineLimit(1)
                        Text("\(r.rounds)")
                        Text("\(r.wins)")
                        Text(Fmt.half(r.duel)).bold()
                        Text("\(Int((r.quote * 100).rounded())) %")
                    }
                    .font(.subheadline.monospacedDigit())
                }
            }
        } header: { Text("Order of Merit · \(virt ? "virtuelles" : "offizielles") HCP") } footer: {
            Text("Jede gemeinsame Runde ist ein Duell nach Stableford: Sieg gegen einen Mitspieler = 1 Duellpunkt, Gleichstand = ½.")
        }
        if rows.count >= 2 {
            Section {
                ScrollView(.horizontal) {
                    Grid(alignment: .center, horizontalSpacing: 14, verticalSpacing: 8) {
                        GridRow {
                            Text("")
                            ForEach(rows) { r in Text(data.name(r.pid)).font(.caption.bold()).lineLimit(1) }
                        }
                        ForEach(rows) { a in
                            GridRow {
                                Text(data.name(a.pid)).font(.caption.bold()).gridColumnAlignment(.leading)
                                ForEach(rows) { b in cell(a.pid, b.pid) }
                            }
                        }
                    }
                }
            } header: { Text("Duell-Bilanz") } footer: { Text("Siege : Niederlagen aus Sicht der Zeile, U = unentschieden.") }
        }
    }

    @ViewBuilder private func cell(_ a: UUID, _ b: UUID) -> some View {
        if a == b { Text("–").foregroundStyle(.secondary) }
        else if let x = h2h["\(a)|\(b)"] {
            HStack(spacing: 2) {
                Text("\(x.w)").bold().foregroundStyle(x.w > x.l ? Color.fairway : x.w < x.l ? .red : .secondary)
                Text(": \(x.l)")
                if x.t > 0 { Text("(\(x.t) U)").font(.caption2).foregroundStyle(.secondary) }
            }
            .font(.subheadline.monospacedDigit())
        } else { Text("nie").font(.caption).foregroundStyle(.secondary) }
    }
}
