import SwiftUI
import SwiftData
import Observation

/// Gemeinsame Auswahl für Statistik und Ranking
@Observable
final class AppState {
    var year: YearFilter = .year(Calendar.current.component(.year, from: .now))
    var virt = false
}

@main
struct GolfScorebuchApp: App {
    @State private var app = AppState()
    @State private var opener = BogeyOpener()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .environment(opener)
                .tint(.fairway)
        }
        .modelContainer(for: [Player.self, Course.self, Round.self, PlayerRound.self])
    }
}

struct ContentView: View {
    @Environment(BogeyOpener.self) private var opener
    @Environment(\.modelContext) private var context

    var body: some View {
        @Bindable var opener = opener
        TabView {
            RoundsListView().tabItem { Label("Runden", systemImage: "flag.fill") }
            StatsView().tabItem { Label("Statistik", systemImage: "chart.line.uptrend.xyaxis") }
            RankingView().tabItem { Label("Ranking", systemImage: "trophy.fill") }
            BriefingView().tabItem { Label("Briefing", systemImage: "map.fill") }
            MoreView().tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
        }
        // .bogey-Datei aus Dateien, Mail, WhatsApp … geöffnet
        .onOpenURL { url in opener.open(url, context: context) }
        .sheet(item: $opener.plan) { BogeyImportSheet(plan: $0) }
        .alert("Datei nicht lesbar", isPresented: Binding(get: { opener.error != nil }, set: { if !$0 { opener.error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(opener.error ?? "") }
    }
}
