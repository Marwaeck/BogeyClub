import SwiftUI

struct EntryDraft: Identifiable {
    let id = UUID()
    var player: Player
    var hcp: Double
    var strokes: [Int]
    var teeName: String?
    var teeRating: Double?
    var teeSlope: Int?
}

/// Editierbare Scorekarte: Spalten = Löcher, Zeilen = Spieler. Symbole wie auf Papier:
/// Kreis = Birdie, Doppelkreis = Eagle, Quadrat = Bogey, Doppelquadrat = Doppelbogey+
struct ScoreGridView: View {
    let pars: [Int]
    var received: [[Int]] = []          // Vorgabeschläge je Spielerzeile
    @Binding var drafts: [EntryDraft]
    var editable = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 4, verticalSpacing: 6) {
                GridRow {
                    Text("Loch").font(.caption.bold()).frame(width: 76, alignment: .leading)
                    ForEach(pars.indices, id: \.self) { i in Text("\(i + 1)").font(.caption.bold()).frame(width: 36) }
                    Text("Σ").font(.caption.bold()).frame(width: 40)
                }
                GridRow {
                    Text("Par").font(.caption).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                    ForEach(pars.indices, id: \.self) { i in Text("\(pars[i])").font(.caption).foregroundStyle(.secondary).frame(width: 36) }
                    Text("\(pars.sum)").font(.caption).foregroundStyle(.secondary).frame(width: 40)
                }
                Divider()
                ForEach(Array(drafts.indices), id: \.self) { r in
                    GridRow {
                        Text(drafts[r].player.name).font(.subheadline).lineLimit(1).frame(width: 76, alignment: .leading)
                        ForEach(pars.indices, id: \.self) { i in
                            StrokeCell(value: binding(r, i), par: pars[i],
                                       dots: r < received.count && i < received[r].count ? received[r][i] : 0,
                                       editable: editable)
                        }
                        Text("\(drafts[r].strokes.sum)").font(.subheadline.bold()).frame(width: 40)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func binding(_ r: Int, _ i: Int) -> Binding<Int> {
        Binding(
            get: { r < drafts.count && i < drafts[r].strokes.count ? drafts[r].strokes[i] : 0 },
            set: { v in
                guard r < drafts.count else { return }
                var s = drafts[r].strokes
                while s.count <= i { s.append(0) }
                s[i] = v
                drafts[r].strokes = s
            })
    }
}

struct StrokeCell: View {
    @Binding var value: Int
    let par: Int
    var dots = 0
    var editable = true

    private var text: Binding<String> {
        Binding(get: { value == 0 ? "" : "\(value)" },
                set: { value = min(Int($0.filter(\.isNumber).prefix(2)) ?? 0, 20) })
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if editable {
                    TextField("·", text: text).keyboardType(.numberPad).multilineTextAlignment(.center)
                } else {
                    Text(value == 0 ? "–" : "\(value)")
                }
            }
            .font(.body.monospacedDigit().weight(.semibold))
            .frame(width: 30, height: 30)
            .overlay(symbol)
            .frame(width: 36, height: 36)
            if dots > 0 {
                Text(String(repeating: "•", count: min(dots, 3))).font(.system(size: 8)).foregroundStyle(Color.fairway).offset(x: -1, y: 0)
            }
        }
    }

    @ViewBuilder private var symbol: some View {
        if value > 0 {
            let d = value - par
            if d <= -2 { Circle().stroke(lineWidth: 1.3).padding(-1).overlay(Circle().stroke(lineWidth: 1.3).padding(-4)) }
            else if d == -1 { Circle().stroke(lineWidth: 1.3).padding(-1) }
            else if d == 1 { Rectangle().stroke(lineWidth: 1.3).padding(-1) }
            else if d >= 2 { Rectangle().stroke(lineWidth: 1.3).padding(-1).overlay(Rectangle().stroke(lineWidth: 1.3).padding(-4)) }
        }
    }
}

struct SymbolLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            Label { Text("Birdie") } icon: { Circle().stroke(lineWidth: 1.2).frame(width: 11, height: 11) }
            Label { Text("Bogey") } icon: { Rectangle().stroke(lineWidth: 1.2).frame(width: 11, height: 11) }
            Label { Text("Vorgabeschlag") } icon: { Text("•").foregroundStyle(Color.fairway) }
            Text("leer = Strich")
        }
        .font(.caption2).foregroundStyle(.secondary)
    }
}
