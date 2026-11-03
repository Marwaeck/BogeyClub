import Foundation
import SwiftData

@Model
final class Player {
    var uid: UUID = UUID()
    var name: String = ""
    /// Offizieller Handicap-Index (WHS)
    var handicapIndex: Double = 54
    @Relationship(deleteRule: .cascade, inverse: \PlayerRound.player)
    var entries: [PlayerRound] = []

    init(name: String, handicapIndex: Double = 54) {
        self.name = name
        self.handicapIndex = handicapIndex
    }
}

@Model
final class Course {
    var uid: UUID = UUID()
    var name: String = ""
    var courseRating: Double = 72
    var slope: Int = 113
    /// Par je Loch (9 oder 18)
    var pars: [Int] = Array(repeating: 4, count: 18)
    /// Lochvorgabe je Loch (1 = schwerstes Loch)
    var strokeIndex: [Int] = Array(1...18)
    @Relationship(inverse: \Round.course)
    var rounds: [Round] = []

    init(name: String, courseRating: Double = 72, slope: Int = 113,
         pars: [Int] = Array(repeating: 4, count: 18), strokeIndex: [Int] = Array(1...18)) {
        self.name = name
        self.courseRating = courseRating
        self.slope = slope
        self.pars = pars
        self.strokeIndex = strokeIndex
    }
}

@Model
final class Round {
    var uid: UUID = UUID()
    var date: Date = Date.now
    var updated: Date = Date.now
    var course: Course?
    var source: String = ""
    @Relationship(deleteRule: .cascade, inverse: \PlayerRound.round)
    var entries: [PlayerRound] = []
    @Attribute(.externalStorage)
    var scanImage: Data?

    init(date: Date = .now, course: Course? = nil) {
        self.date = date
        self.course = course
    }
}

@Model
final class PlayerRound {
    var player: Player?
    var round: Round?
    /// Handicap-Index am Spieltag
    var handicapIndexAtRound: Double = 54
    /// Schläge je Loch, 0 = Strich / nicht gespielt
    var strokes: [Int] = []
    /// Optional eigener Abschlag (überschreibt CR/Slope des Platzes)
    var teeName: String?
    var teeRating: Double?
    var teeSlope: Int?

    init(handicapIndexAtRound: Double, strokes: [Int]) {
        self.handicapIndexAtRound = handicapIndexAtRound
        self.strokes = strokes
    }
}

// MARK: - Wertobjekte für die Berechnungen

struct PlayerV: Identifiable, Hashable {
    let id: UUID
    var name: String
    var hcp: Double
}

struct CourseV: Identifiable, Hashable {
    let id: UUID
    var name: String
    var cr: Double
    var slope: Int
    var pars: [Int]
    var si: [Int]
    var par: Int { pars.reduce(0, +) }
    var holes: Int { pars.count }
}

struct EntryV: Hashable {
    var playerID: UUID
    var hcp: Double
    var strokes: [Int]
    var teeName: String?
    var teeCR: Double?
    var teeSlope: Int?
}

struct RoundV: Identifiable, Hashable {
    let id: UUID
    var day: String          // "yyyy-MM-dd"
    var date: Date
    var updated: Date
    var courseID: UUID?
    var entries: [EntryV]
}

/// Momentaufnahme aller Daten – alle Auswertungen arbeiten darauf.
struct GolfData {
    var players: [PlayerV]
    var courses: [CourseV]
    var rounds: [RoundV]

    init(players: [Player], courses: [Course], rounds: [Round]) {
        self.players = players.map { PlayerV(id: $0.uid, name: $0.name, hcp: $0.handicapIndex) }
        self.courses = courses.map { CourseV(id: $0.uid, name: $0.name, cr: $0.courseRating, slope: $0.slope, pars: $0.pars, si: $0.strokeIndex) }
        self.rounds = rounds.map { r in
            RoundV(id: r.uid, day: Day.key(r.date), date: r.date, updated: r.updated, courseID: r.course?.uid,
                   entries: r.entries.compactMap { e in
                       guard let p = e.player else { return nil }
                       return EntryV(playerID: p.uid, hcp: e.handicapIndexAtRound, strokes: e.strokes,
                                     teeName: e.teeName, teeCR: e.teeRating, teeSlope: e.teeSlope)
                   })
        }
        .sorted { $0.day != $1.day ? $0.day < $1.day : $0.updated < $1.updated }
    }

    func course(_ id: UUID?) -> CourseV? { guard let id else { return nil }; return courses.first { $0.id == id } }
    func player(_ id: UUID) -> PlayerV? { players.first { $0.id == id } }
    func name(_ id: UUID) -> String { player(id)?.name ?? "Unbekannt" }
}

enum Day {
    private static let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = .current; return c }()
    static func key(_ d: Date) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    static func year(_ key: String) -> Int { Int(key.prefix(4)) ?? 0 }
    static func date(_ key: String) -> Date {
        let p = key.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return .now }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2], hour: 12)) ?? .now
    }
}
