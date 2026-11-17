import SwiftUI
import SwiftData

struct RoundsListView: View {
    @Query(sort: \Round.date, order: .reverse) private var rounds: [Round]
    @Environment(\.modelContext) private var context
    @State private var showNew = false
    @State private var showLink = false
    @State private var editing: Round?
    @State private var sharing: SharedFile?
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(rounds) { r in
                    Button { editing = r } label: { RoundRow(round: r) }.foregroundStyle(.primary)
                        .swipeActions(edge: .leading) {
                            Button { share(r) } label: { Label("Teilen", systemImage: "square.and.arrow.up") }.tint(.fairway)
                        }
                        .contextMenu {
                            Button { share(r) } label: { Label("Als Bogey-Datei teilen", systemImage: "square.and.arrow.up") }
                        }
                }
                .onDelete { idx in idx.forEach { context.delete(rounds[$0]) } }
            }
            .overlay {
                if rounds.isEmpty {
                    ContentUnavailableView {
                        Label("Noch keine Runden", systemImage: "flag")
                    } description: {
                        Text("Erfasse deine erste Runde – per Foto der Scorekarte, TAG-Heuer-Link oder von Hand.")
                    } actions: {
                        Button("Runde erfassen") { showNew = true }.buttonStyle(.borderedProminent).tint(.fairway)
                    }
                }
            }
            .navigationTitle("Runden")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showNew = true } label: { Label("Neue Runde", systemImage: "square.and.pencil") }
                        Button { showLink = true } label: { Label("Per TAG-Heuer-Link", systemImage: "link") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) { RoundEditorView(round: nil) }
            .sheet(isPresented: $showLink) { RoundEditorView(round: nil, startWithLink: true) }
            .sheet(item: $editing) { RoundEditorView(round: $0) }
            .sheet(item: $sharing) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
            .alert("Teilen nicht möglich", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(shareError ?? "") }
        }
    }
}

extension RoundsListView {
    /// Runde als .bogey-Datei an Freunde – sie öffnen sie in ihrer Bogey-Club-App
    fileprivate func share(_ r: Round) {
        do { sharing = SharedFile(url: try BogeyTransfer.roundFile(r)) }
        catch { shareError = "Für diese Runde fehlt der Platz." }
    }
}

struct RoundRow: View {
    let round: Round

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(round.date, format: .dateTime.day()).font(.title2.bold())
                Text(round.date.formatted(.dateTime.month(.abbreviated).year(.twoDigits).locale(Locale(identifier: "de_DE")))).font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            }
            .frame(width: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(round.course?.name ?? "Platz gelöscht").font(.headline).lineLimit(1)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        guard let c = round.course else { return "" }
        let cv = CourseV(id: c.uid, name: c.name, cr: c.courseRating, slope: c.slope, pars: c.pars, si: c.strokeIndex)
        return round.entries.compactMap { e -> String? in
            guard let p = e.player else { return nil }
            let r = Golf.result(EntryV(playerID: p.uid, hcp: e.handicapIndexAtRound, strokes: e.strokes, teeCR: e.teeRating, teeSlope: e.teeSlope), cv)
            return "\(p.name) \(r.gross)\(r.complete ? "" : "*") · \(r.pts) P."
        }.sorted().joined(separator: "   ")
    }
}
