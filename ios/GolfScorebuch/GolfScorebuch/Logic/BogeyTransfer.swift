import Foundation
import SwiftData
import UniformTypeIdentifiers
import BogeyScan

/// Bogey-Datei (.bogey): Austausch mit den anderen Bogey-Club-Apps (Web, Mac, Windows, Android) und mit Freunden.
extension UTType {
    static let bogey = UTType(exportedAs: BogeyFile.typeIdentifier, conformingTo: .data)
}

extension Player { var exportID: String { bogeyID.isEmpty ? uid.uuidString.lowercased() : bogeyID } }
extension Course { var exportID: String { bogeyID.isEmpty ? uid.uuidString.lowercased() : bogeyID } }
extension Round { var exportID: String { bogeyID.isEmpty ? uid.uuidString.lowercased() : bogeyID } }

enum BogeyTransfer {
    // MARK: Export

    static func dto(_ p: Player) -> BogeyPlayer { BogeyPlayer(id: p.exportID, name: p.name, hcp: p.handicapIndex) }

    static func dto(_ c: Course) -> BogeyCourse {
        BogeyCourse(id: c.exportID, name: c.name, cr: c.courseRating, slope: c.slope, pars: c.pars, si: c.strokeIndex)
    }

    static func dto(_ r: Round) -> BogeyRound? {
        guard let c = r.course else { return nil }
        let entries = r.entries.compactMap { e -> BogeyEntry? in
            guard let p = e.player else { return nil }
            return BogeyEntry(playerId: p.exportID, hcp: e.handicapIndexAtRound, strokes: e.strokes,
                              tee: e.teeName, cr: e.teeRating, slope: e.teeSlope)
        }
        return BogeyRound(id: r.exportID, courseId: c.exportID, date: Day.key(r.date), entries: entries,
                          source: r.source.isEmpty ? nil : r.source, updatedAt: (r.updated.timeIntervalSince1970 * 1000).rounded())
    }

    /// Alle Daten als .bogey-Datei im temporären Ordner (zum Teilen oder Sichern)
    static func backupFile(players: [Player], courses: [Course], rounds: [Round]) throws -> URL {
        let doc = BogeyDocument(kind: .backup, players: players.map(dto), courses: courses.map(dto), rounds: rounds.compactMap(dto))
        return try write(BogeyFile.encode(doc), name: "Bogey-Club-Backup-\(Day.key(.now))")
    }

    /// Eine Runde mit ihren Spielern und dem Platz – zum Weitergeben an Freunde
    static func roundFile(_ r: Round) throws -> URL {
        guard let rd = dto(r), let c = r.course else { throw BogeyFileError.notBogey }
        let players = r.entries.compactMap(\.player).map(dto)
        let doc = BogeyDocument(kind: .round, players: players, courses: [dto(c)], rounds: [rd])
        return try write(BogeyFile.encode(doc), name: "Bogey-Club-Runde-\(rd.date)-\(slug(c.name))")
    }

    private static func write(_ data: Data, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Bogey", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name).appendingPathExtension(BogeyFile.fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func slug(_ s: String) -> String {
        let plain = s.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
        let parts = plain.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.joined(separator: "-")
    }

    // MARK: Import

    /// Was beim Einspielen passiert – wird vor dem Bestätigen angezeigt
    struct Plan {
        let document: BogeyDocument
        let kind: BogeyDocument.Kind
        var newPlayers: [BogeyPlayer] = []
        var matchedPlayers: [String: Player] = [:]   // ID in der Datei → vorhandener Spieler
        var newCourses: [BogeyCourse] = []
        var matchedCourses: [String: Course] = [:]
        var newRounds = 0
        var updatedRounds = 0

        var title: String {
            if kind == .round, let r = document.rounds.first {
                let course = document.courses.first { $0.id == r.courseId }?.name ?? "unbekanntem Platz"
                return "Runde vom \(Fmt.day(r.date)) auf \(course)"
            }
            return "Backup" + (document.exportedAt.flatMap(parseISODate).map { " vom \(Fmt.date($0))" } ?? "")
        }

        var details: [String] {
            var out: [String] = []
            if kind == .round {
                out.append("Spieler: " + document.players.map(\.name).joined(separator: ", "))
                out.append("\(matchedPlayers.count) Spieler bei dir gefunden" + (newPlayers.isEmpty ? "" : ", \(newPlayers.count) neu (\(newPlayers.map(\.name).joined(separator: ", ")))"))
                out.append(newCourses.isEmpty ? "Platz ist schon vorhanden" : "Platz wird neu angelegt")
                if updatedRounds > 0 { out.append("Diese Runde gibt es schon – sie wird aktualisiert.") }
                out.append("Deine Spieler und Plätze werden nicht verändert.")
            } else {
                out.append("\(document.players.count) Spieler (\(newPlayers.count) neu, \(matchedPlayers.count) aktualisiert)")
                out.append("\(document.courses.count) Plätze (\(newCourses.count) neu, \(matchedCourses.count) aktualisiert)")
                out.append("\(newRounds + updatedRounds) Runden (\(newRounds) neu, \(updatedRounds) aktualisiert)")
                out.append("Gelöscht wird nichts. Bilder und Platzkarten nutzt die iPhone-App nicht.")
            }
            return out
        }
    }

    private static func norm(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
    }

    static func plan(_ doc: BogeyDocument, context: ModelContext) throws -> Plan {
        let players = try context.fetch(FetchDescriptor<Player>())
        let courses = try context.fetch(FetchDescriptor<Course>())
        let rounds = try context.fetch(FetchDescriptor<Round>())
        var plan = Plan(document: doc, kind: doc.kind)
        for p in doc.players {
            let hit = players.first { $0.exportID == p.id || $0.uid.uuidString.lowercased() == p.id.lowercased() }
                ?? players.first { norm($0.name) == norm(p.name) }
            if let hit { plan.matchedPlayers[p.id] = hit } else { plan.newPlayers.append(p) }
        }
        for c in doc.courses {
            let hit = courses.first { $0.exportID == c.id || $0.uid.uuidString.lowercased() == c.id.lowercased() }
                ?? courses.first { norm($0.name) == norm(c.name) && $0.pars == c.pars }
            if let hit { plan.matchedCourses[c.id] = hit } else { plan.newCourses.append(c) }
        }
        let ids = Set(rounds.map(\.exportID))
        plan.updatedRounds = doc.rounds.filter { ids.contains($0.id) }.count
        plan.newRounds = doc.rounds.count - plan.updatedRounds
        return plan
    }

    /// Spielt die Datei ein. Liefert die eingespielte Runde (bei einer Runden-Datei), um sie gleich zu zeigen.
    @discardableResult
    static func apply(_ plan: Plan, context: ModelContext) throws -> Round? {
        let doc = plan.document
        var playerFor = plan.matchedPlayers, courseFor = plan.matchedCourses
        if plan.kind == .backup {   // Backup: vorhandene Einträge mit den Werten aus der Datei überschreiben
            for p in doc.players { if let hit = playerFor[p.id] { hit.name = p.name; hit.handicapIndex = p.hcp } }
            for c in doc.courses {
                if let hit = courseFor[c.id] { hit.name = c.name; hit.courseRating = c.cr; hit.slope = c.slope; hit.pars = c.pars; hit.strokeIndex = c.si }
            }
        }
        for p in plan.newPlayers {
            let n = Player(name: p.name, handicapIndex: p.hcp); n.bogeyID = p.id
            context.insert(n); playerFor[p.id] = n
        }
        for c in plan.newCourses {
            let n = Course(name: c.name, courseRating: c.cr, slope: c.slope, pars: c.pars, strokeIndex: c.si); n.bogeyID = c.id
            context.insert(n); courseFor[c.id] = n
        }
        let existing = try context.fetch(FetchDescriptor<Round>())
        var last: Round?
        for rd in doc.rounds {
            let r: Round
            if let hit = existing.first(where: { $0.exportID == rd.id }) {
                r = hit
                for e in r.entries { context.delete(e) }
            } else {
                r = Round(date: Day.date(rd.date)); r.bogeyID = rd.id
                context.insert(r)
            }
            r.date = Day.date(rd.date)
            r.course = courseFor[rd.courseId]
            r.source = rd.source ?? r.source
            r.updated = rd.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
            let holes = r.course?.pars.count ?? rd.entries.first?.strokes.count ?? 18
            for e in rd.entries {
                guard let player = playerFor[e.playerId] else { continue }
                let pr = PlayerRound(handicapIndexAtRound: e.hcp, strokes: Golf.fit(e.strokes, holes))
                pr.teeName = e.tee; pr.teeRating = e.cr; pr.teeSlope = e.slope
                context.insert(pr)
                pr.player = player
                pr.round = r
            }
            last = r
        }
        try context.save()
        return plan.kind == .round ? last : nil
    }

    static func message(for error: Error) -> String {
        switch error as? BogeyFileError {
        case .newerVersion: return "Diese Datei stammt aus einer neueren Bogey-Club-Version. Bitte zuerst die App aktualisieren."
        case .corrupt: return "Die Datei ist beschädigt."
        default: return "Das ist keine Bogey-Datei und kein Bogey-Club-Backup."
        }
    }
}

/// Liest Zeitstempel mit und ohne Millisekunden (die Web-App schreibt …T18:30:19.123Z)
func parseISODate(_ s: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: s)
}
