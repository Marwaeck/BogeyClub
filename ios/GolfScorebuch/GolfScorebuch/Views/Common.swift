import SwiftUI

enum Fmt {
    private static let de = Locale(identifier: "de_DE")
    static func one(_ v: Double?) -> String {
        guard let v else { return "–" }
        return v.formatted(.number.precision(.fractionLength(1)).locale(de))
    }
    static func half(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : one(v)
    }
    static func vs(_ v: Int?) -> String {
        guard let v else { return "–" }
        return v == 0 ? "±0" : (v > 0 ? "+\(v)" : "−\(-v)")
    }
    static func vs(_ v: Double?) -> String {
        guard let v else { return "–" }
        if abs(v) < 0.05 { return "±0" }
        return (v > 0 ? "+" : "−") + one(abs(v))
    }
    static func date(_ d: Date) -> String { d.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year().locale(de)) }
    static func day(_ key: String) -> String { date(Day.date(key)) }
}

extension Color {
    static let fairway = Color(red: 0.11, green: 0.40, blue: 0.25)
    static func tier(_ t: BadgeTier) -> Color {
        switch t {
        case .copper: return Color(red: 0.54, green: 0.35, blue: 0.27)
        case .bronze: return Color(red: 0.66, green: 0.41, blue: 0.18)
        case .silver: return Color(red: 0.49, green: 0.54, blue: 0.58)
        case .gold: return Color(red: 0.72, green: 0.54, blue: 0.04)
        case .green: return .fairway
        case .neg: return Color(red: 0.61, green: 0.11, blue: 0.11)
        }
    }
}

struct KPI: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground)))
    }
}

struct KPIGrid: View {
    let items: [(String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(items.indices, id: \.self) { i in KPI(value: items[i].0, label: items[i].1) }
        }
    }
}

/// Medaille für ein Badge
struct BadgeView: View {
    let def: BadgeDef
    let state: BadgeState
    let played: Int

    var on: Bool { state.count > 0 }
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if on {
                    (def.neg ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle()))
                        .fill(Color.tier(def.tier))
                        .overlay((def.neg ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle())).stroke(.white.opacity(0.35), lineWidth: 3).padding(2))
                } else {
                    (def.neg ? AnyShape(RoundedRectangle(cornerRadius: 10)) : AnyShape(Circle()))
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [4, 3])).foregroundStyle(.tertiary)
                }
                Text(def.short).font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(on ? .white : .secondary)
            }
            .frame(width: 52, height: 52)
            .rotationEffect(.degrees(def.neg ? -6 : 0))
            Text(def.label).font(.caption.weight(.semibold)).foregroundStyle(on ? .primary : .secondary)
            if let sub = def.sub { Text(sub).font(.caption2).multilineTextAlignment(.center) }
            Text(caption).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).stroke(def.neg ? Color.tier(.neg) : Color(.separator), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint(def.desc)
    }

    var caption: String {
        if on {
            if def.milestone != nil { return "erreicht \(Fmt.day(state.first ?? ""))" }
            return "\(state.count)× · zuerst \(Fmt.day(state.first ?? ""))"
        }
        if let m = def.milestone { return "\(played) / \(m)" }
        return "noch offen"
    }
}

struct BadgeGrid: View {
    let data: GolfData
    let pid: UUID
    var body: some View {
        let b = data.playerBadges(pid)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
            ForEach(BadgeDef.all) { d in BadgeView(def: d, state: b.states[d.id] ?? BadgeState(), played: b.played) }
        }
    }
}

/// Jahr-Auswahl und Wertung (offiziell / virtuell)
struct FilterBar: View {
    let years: [Int]
    @Binding var year: YearFilter
    @Binding var virtual: Bool
    var showScoring = true
    var body: some View {
        Picker("Jahr", selection: $year) {
            Text("Alle Jahre").tag(YearFilter.all)
            ForEach(years, id: \.self) { Text(String($0)).tag(YearFilter.year($0)) }
        }
        if showScoring {
            Picker("Wertung", selection: $virtual) {
                Text("Offizielles HCP").tag(false)
                Text("Virtuelles HCP").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }
}

func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
