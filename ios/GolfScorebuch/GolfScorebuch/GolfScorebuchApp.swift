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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .tint(.fairway)
        }
        .modelContainer(for: [Player.self, Course.self, Round.self, PlayerRound.self])
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            RoundsListView().tabItem { Label("Runden", systemImage: "flag.fill") }
            StatsView().tabItem { Label("Statistik", systemImage: "chart.line.uptrend.xyaxis") }
            RankingView().tabItem { Label("Ranking", systemImage: "trophy.fill") }
            BriefingView().tabItem { Label("Briefing", systemImage: "map.fill") }
            MoreView().tabItem { Label("Mehr", systemImage: "ellipsis.circle") }
        }
    }
}
