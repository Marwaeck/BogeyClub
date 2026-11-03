import Foundation

enum YearFilter: Hashable {
    case all
    case year(Int)

    func contains(_ day: String) -> Bool {
        switch self {
        case .all: return true
        case .year(let y): return Day.year(day) == y
        }
    }
    var label: String {
        switch self {
        case .all: return "Alle Jahre"
        case .year(let y): return String(y)
        }
    }
    var seasonTitle: String {
        switch self {
        case .all: return "Alle Jahre"
        case .year(let y): return "Saison \(y)"
        }
    }
}

// MARK: - Virtuelles Handicap

extension GolfData {
    /// Score-Differentials eines Spielers (chronologisch), optional nur vor einem Datum und ohne eine Runde
    func playerDiffs(_ pid: UUID, before: String = "9999-12-31", exclude: UUID? = nil) -> [Double] {
        var ds: [Double] = []
        for r in rounds where r.day < before && r.id != exclude {
            guard let c = course(r.courseID) else { continue }
            for e in r.entries where e.playerID == pid {
                var d = Golf.scoreDifferential(e, c)
                if d == nil, let d9 = Golf.nineHoleDiff(e, c) {
                    d = d9 + Golf.expected9(Golf.hiFromDiffs(Array(ds.suffix(20))) ?? e.hcp)
                }
                if let d { ds.append(d) }
            }
        }
        return ds
    }

    func virtualHI(_ pid: UUID, before: String = "9999-12-31", exclude: UUID? = nil) -> (hi: Double?, count: Int) {
        let last = Array(playerDiffs(pid, before: before, exclude: exclude).suffix(20))
        return (Golf.hiFromDiffs(last), last.count)
    }

    var years: [Int] { Array(Set(rounds.map { Day.year($0.day) }).filter { $0 > 0 }).sorted(by: >) }
}

// MARK: - Jahresstatistik

struct RoundPoint: Identifiable {
    let id = UUID()
    let day: String
    let roundID: UUID
    let course: String
    let n: Int
    let gross: Int?
    let vsPar: Int?
    let net: Int?
    let pts: Int
    let vpts: Int
    let vnet: Int?
    let vhi: Double?
    var date: Date { Day.date(day) }
}

struct PlayerYearStats: Identifiable {
    let player: PlayerV
    let points: [RoundPoint]
    let virtual: (hi: Double?, count: Int)
    var id: UUID { player.id }

    var rounds: Int { points.count }
    var r18: [RoundPoint] { points.filter { $0.n == 18 } }
    var f18: [RoundPoint] { r18.filter { $0.gross != nil } }
    var nine: Int { points.filter { $0.n != 18 }.count }
    var avgGross: Double? { f18.compactMap(\.gross).average }
    var bestGross: Int? { f18.compactMap(\.gross).min() }
    var avgVs: Double? { f18.compactMap(\.vsPar).average }
    var avgNet: Double? { f18.compactMap(\.net).average }
    var avgVNet: Double? { f18.compactMap(\.vnet).average }
    var avgPts: Double? { r18.map(\.pts).average }
    var bestPts: Int? { r18.map(\.pts).max() }
    var avgVPts: Double? { r18.map(\.vpts).average }
    var bestVPts: Int? { r18.map(\.vpts).max() }
    var totalPts: Int { points.map(\.pts).sum }
}

extension GolfData {
    func yearStats(_ y: YearFilter, virt: Bool) -> [PlayerYearStats] {
        players.compactMap { p in
            var pts: [RoundPoint] = []
            for r in rounds where y.contains(r.day) {
                guard let c = course(r.courseID) else { continue }
                for e in r.entries where e.playerID == p.id {
                    let res = Golf.result(e, c)
                    let vh = virtualHI(p.id, before: r.day, exclude: r.id).hi
                    var ve = e; ve.hcp = vh ?? e.hcp
                    let vres = Golf.result(ve, c)
                    pts.append(RoundPoint(day: r.day, roundID: r.id, course: c.name, n: res.n,
                                          gross: res.complete ? res.gross : nil, vsPar: res.complete ? res.vsPar : nil,
                                          net: res.complete ? res.net : nil, pts: res.pts, vpts: vres.pts,
                                          vnet: res.complete ? vres.net : nil, vhi: vh))
                }
            }
            guard !pts.isEmpty else { return nil }
            return PlayerYearStats(player: p, points: pts, virtual: virtualHI(p.id))
        }
        .sorted { (virt ? $0.avgVPts : $0.avgPts) ?? 0 > (virt ? $1.avgVPts : $1.avgPts) ?? 0 }
    }
}

// MARK: - Order of Merit

struct MeritRow: Identifiable {
    let pid: UUID
    var rounds = 0, wins = 0, games = 0, place = 0
    var duel: Double = 0
    var id: UUID { pid }
    var avgPlace: Double { rounds > 0 ? Double(place) / Double(rounds) : 0 }
    var quote: Double { games > 0 ? duel / Double(games) : 0 }
}

struct H2H { var w = 0, t = 0, l = 0 }

extension GolfData {
    /// Jede Runde mit ≥2 Spielern: Sieg gegen einen Mitspieler = 1 Duellpunkt, Gleichstand = ½
    func merit(_ y: YearFilter, virt: Bool) -> (rows: [MeritRow], h2h: [String: H2H]) {
        var tbl: [UUID: MeritRow] = [:], h2h: [String: H2H] = [:]
        for r in rounds where y.contains(r.day) {
            guard let c = course(r.courseID) else { continue }
            let es = r.entries.filter { player($0.playerID) != nil }
            guard es.count >= 2 else { continue }
            let sc: [(pid: UUID, v: Int)] = es.map { e in
                var x = e
                if virt { x.hcp = virtualHI(e.playerID, before: r.day, exclude: r.id).hi ?? e.hcp }
                return (e.playerID, Golf.result(x, c).pts)
            }
            let top = sc.map(\.v).max() ?? 0
            for (i, a) in sc.enumerated() {
                var t = tbl[a.pid] ?? MeritRow(pid: a.pid)
                let better = sc.filter { $0.v > a.v }.count
                let tied = sc.enumerated().filter { $0.offset != i && $0.element.v == a.v }.count
                t.rounds += 1; t.place += 1 + better; t.games += sc.count - 1
                t.duel += Double(sc.count - 1 - better - tied) + Double(tied) / 2
                if a.v == top { t.wins += 1 }
                tbl[a.pid] = t
                for (j, b) in sc.enumerated() where j != i {
                    let k = "\(a.pid)|\(b.pid)"
                    var h = h2h[k] ?? H2H()
                    if a.v > b.v { h.w += 1 } else if a.v == b.v { h.t += 1 } else { h.l += 1 }
                    h2h[k] = h
                }
            }
        }
        let rows = tbl.values.sorted {
            if $0.duel != $1.duel { return $0.duel > $1.duel }
            if $0.wins != $1.wins { return $0.wins > $1.wins }
            return $0.avgPlace < $1.avgPlace
        }
        return (rows, h2h)
    }
}

// MARK: - Badges

enum BadgeTier { case copper, bronze, silver, gold, green, neg }

struct BadgeInfo {
    var full = false, n18 = false
    var gross = 0, pts = 0, streak = 0, triple2 = 0, birdies = 0, eagles = 0
}

struct BadgeDef: Identifiable {
    let id: String
    let label: String
    var sub: String? = nil
    let short: String
    let tier: BadgeTier
    var neg = false
    let desc: String
    var milestone: Int? = nil
    var test: (BadgeInfo) -> Int = { _ in 0 }

    static let all: [BadgeDef] = [
        BadgeDef(id: "u110", label: "Unter 110", short: "<110", tier: .copper, desc: "18-Loch-Runde mit weniger als 110 Schlägen", test: { $0.full && $0.gross < 110 ? 1 : 0 }),
        BadgeDef(id: "u100", label: "Unter 100", short: "<100", tier: .bronze, desc: "18-Loch-Runde mit weniger als 100 Schlägen", test: { $0.full && $0.gross < 100 ? 1 : 0 }),
        BadgeDef(id: "u90", label: "Unter 90", short: "<90", tier: .silver, desc: "18-Loch-Runde mit weniger als 90 Schlägen", test: { $0.full && $0.gross < 90 ? 1 : 0 }),
        BadgeDef(id: "u80", label: "Unter 80", short: "<80", tier: .gold, desc: "18-Loch-Runde mit weniger als 80 Schlägen", test: { $0.full && $0.gross < 80 ? 1 : 0 }),
        BadgeDef(id: "p40", label: "40+ Punkte", short: "40+", tier: .green, desc: "Mindestens 40 Stableford-Punkte in einer 18-Loch-Runde", test: { $0.n18 && $0.pts >= 40 ? 1 : 0 }),
        BadgeDef(id: "birdie", label: "Birdie", short: "−1", tier: .silver, desc: "Ein Loch einen Schlag unter Par", test: { $0.birdies }),
        BadgeDef(id: "eagle", label: "Eagle", short: "−2", tier: .gold, desc: "Ein Loch zwei Schläge unter Par", test: { $0.eagles }),
        BadgeDef(id: "par3", label: "3 Pars in Reihe", short: "3×P", tier: .green, desc: "Drei Löcher hintereinander Par oder besser", test: { $0.streak >= 3 ? 1 : 0 }),
        BadgeDef(id: "666", label: "666", sub: "3× Doppelbogey in Folge", short: "666", tier: .neg, neg: true, desc: "Negativ-Badge: drei Doppelbogeys hintereinander", test: { $0.triple2 }),
        BadgeDef(id: "r20", label: "20 Runden", short: "20", tier: .silver, desc: "20 gespielte Runden (9 oder 18 Loch)", milestone: 20),
        BadgeDef(id: "r50", label: "50 Runden", short: "50", tier: .gold, desc: "50 gespielte Runden (9 oder 18 Loch)", milestone: 50)
    ]
}

struct BadgeState {
    var count = 0
    var first: String?
    var course: String?
    var firstEver: String?
}

extension GolfData {
    func playerBadges(_ pid: UUID, _ y: YearFilter = .all) -> (states: [String: BadgeState], played: Int) {
        var out = Dictionary(uniqueKeysWithValues: BadgeDef.all.map { ($0.id, BadgeState()) })
        var played = 0
        for r in rounds {
            guard let c = course(r.courseID) else { continue }
            for e in r.entries where e.playerID == pid {
                let res = Golf.result(e, c), st = Golf.fit(e.strokes, c.holes)
                var info = BadgeInfo()
                var run = 0, run2 = 0
                for (i, v) in st.enumerated() {
                    run = v > 0 && v <= c.pars[i] ? run + 1 : 0
                    info.streak = max(info.streak, run)
                    run2 = v > 0 && v - c.pars[i] == 2 ? run2 + 1 : 0
                    if run2 == 3 { info.triple2 += 1; run2 = 0 }
                    if v > 0 && v - c.pars[i] == -1 { info.birdies += 1 }
                    if v > 0 && v - c.pars[i] == -2 { info.eagles += 1 }
                }
                info.full = c.holes == 18 && res.complete
                info.n18 = c.holes == 18
                info.gross = res.gross; info.pts = res.pts
                played += 1
                let counts = y.contains(r.day)
                for b in BadgeDef.all {
                    var o = out[b.id]!
                    if let m = b.milestone {
                        if played == m {
                            o.firstEver = r.day
                            if counts { o.count = 1; o.first = r.day; o.course = c.name }
                        }
                    } else {
                        let k = b.test(info)
                        if k > 0 {
                            if o.firstEver == nil { o.firstEver = r.day }
                            if counts { o.count += k; if o.first == nil { o.first = r.day; o.course = c.name } }
                        }
                    }
                    out[b.id] = o
                }
            }
        }
        return (out, played)
    }

    func earnedCount(_ pid: UUID) -> Int {
        let s = playerBadges(pid).states
        return BadgeDef.all.filter { !$0.neg && (s[$0.id]?.count ?? 0) > 0 }.count
    }
}

// MARK: - Spieler-Analyse

struct FrontBack: Identifiable {
    let id = UUID()
    let day: String, course: String
    let f: Int, b: Int, fp: Int, bp: Int
}

struct CourseHoles {
    let course: CourseV
    var rounds = 0
    var s: [[Int]]
    var p: [[Int]]
}

struct Analysis {
    var dist: [String: Int] = ["eagle": 0, "birdie": 0, "par": 0, "bogey": 0, "double": 0, "triple": 0, "strich": 0]
    var byPar: [Int: [(d: Int, p: Int)]] = [:]
    var fb: [FrontBack] = []
    var courses: [UUID: CourseHoles] = [:]
}

struct HIPoint: Identifiable {
    let day: String
    let hi: Double
    var id: String { day }
    var date: Date { Day.date(day) }
}

extension GolfData {
    func analysis(_ pid: UUID, _ y: YearFilter) -> Analysis {
        var a = Analysis()
        for r in rounds where y.contains(r.day) {
            guard let c = course(r.courseID) else { continue }
            for e in r.entries where e.playerID == pid {
                let res = Golf.result(e, c), st = Golf.fit(e.strokes, c.holes)
                for (i, v) in st.enumerated() {
                    let par = c.pars[i]
                    guard v > 0 else { a.dist["strich", default: 0] += 1; continue }
                    let d = v - par
                    let key = d <= -2 ? "eagle" : d == -1 ? "birdie" : d == 0 ? "par" : d == 1 ? "bogey" : d == 2 ? "double" : "triple"
                    a.dist[key, default: 0] += 1
                    a.byPar[par, default: []].append((d, res.hp[i]))
                }
                if c.holes == 18 && res.complete {
                    a.fb.append(FrontBack(day: r.day, course: c.name,
                                          f: Array(st[0..<9]).sum - Array(c.pars[0..<9]).sum,
                                          b: Array(st[9..<18]).sum - Array(c.pars[9..<18]).sum,
                                          fp: Array(res.hp[0..<9]).sum, bp: Array(res.hp[9..<18]).sum))
                }
                var ch = a.courses[c.id] ?? CourseHoles(course: c, s: Array(repeating: [], count: c.holes), p: Array(repeating: [], count: c.holes))
                ch.rounds += 1
                for (i, v) in st.enumerated() { if v > 0 { ch.s[i].append(v) }; ch.p[i].append(res.hp[i]) }
                a.courses[c.id] = ch
            }
        }
        return a
    }

    func hiTimeline(_ pid: UUID, _ y: YearFilter) -> [HIPoint] {
        let days = Array(Set(rounds.filter { y.contains($0.day) && $0.entries.contains { $0.playerID == pid } }.map(\.day))).sorted()
        return days.compactMap { d in
            Golf.hiFromDiffs(Array(playerDiffs(pid, before: d + "z").suffix(20))).map { HIPoint(day: d, hi: $0) }
        }
    }
}

// MARK: - Prognose

struct Forecast {
    var none = true
    var exp = 0, vsPar = 0, stb = 0, ph = 0, rounds = 0
    var good: Int?, vstb: Int?, vph: Int?
    var histCount = 0
    var histAvgGross: Double?, histAvgPts: Double?
}

extension GolfData {
    /// Erwartet = CR + Ø der letzten 10 Differentials × Slope/113 (9 Loch: halbes Differential)
    func forecast(_ p: PlayerV, _ c: CourseV) -> Forecast {
        var f = Forecast()
        let n = c.holes, k = n == 18 ? 1.0 : 0.5, par = Double(c.par), sl = Double(c.slope > 0 ? c.slope : 113), base = n == 18 ? 36.0 : 18.0
        var hist: [Golf.Result] = []
        for r in rounds where r.courseID == c.id {
            for e in r.entries where e.playerID == p.id { hist.append(Golf.result(e, c)) }
        }
        f.histCount = hist.count
        f.histAvgGross = hist.filter(\.complete).map(\.gross).average
        f.histAvgPts = hist.map(\.pts).average
        let ds = Array(playerDiffs(p.id).suffix(20))
        guard !ds.isEmpty else { return f }
        f.none = false
        let avgD = Array(ds.suffix(10)).average ?? 0, v = Golf.hiFromDiffs(ds)
        let exp = c.cr + avgD * k * sl / 113
        f.exp = Golf.jsRound(exp); f.vsPar = f.exp - c.par; f.rounds = ds.count
        if let v { f.good = Golf.jsRound(c.cr + v * k * sl / 113) }
        f.ph = Golf.courseHcp(p.hcp, c)
        f.stb = max(0, Golf.jsRound(base - (exp - par - Double(f.ph))))
        if let v {
            let vph = Golf.courseHcp(v, c)
            f.vph = vph
            f.vstb = max(0, Golf.jsRound(base - (exp - par - Double(vph))))
        }
        return f
    }
}

// MARK: - Saisonrückblick

struct Best { let value: Int; let pid: UUID; let course: String; let day: String }

struct SeasonPlayer: Identifiable {
    let pid: UUID, name: String
    let rounds: Int
    let avgPts: Double?, avgGross: Double?
    let bestGross: Best?, bestPts: Best?
    let firstHalf: Double?, secondHalf: Double?
    let hiStart: Double?, hiEnd: Double?
    let earned: [(badge: BadgeDef, count: Int, isNew: Bool)]
    var id: UUID { pid }
}

struct Season {
    let filter: YearFilter
    let rounds: [RoundV]
    let courses: Int
    let players: [SeasonPlayer]
    let bestG: Best?, bestP: Best?
    let birdies: Int, devils: Int
    let merit: (rows: [MeritRow], h2h: [String: H2H])
}

extension GolfData {
    func season(_ y: YearFilter) -> Season {
        let rs = rounds.filter { y.contains($0.day) && course($0.courseID) != nil }
        let pids = Array(Set(rs.flatMap { $0.entries.map(\.playerID) })).filter { player($0) != nil }
        let next: String, start: String
        switch y { case .all: next = "9999-12-31"; start = "0000-01-01"; case .year(let v): next = "\(v + 1)-01-01"; start = "\(v)-01-01" }
        var bestG: Best?, bestP: Best?, birdies = 0, devils = 0
        var players: [SeasonPlayer] = []
        for pid in pids {
            var r18: [(pts: Int, gross: Int?, course: String, day: String)] = []
            var count = 0
            for r in rs {
                let c = course(r.courseID)!
                for e in r.entries where e.playerID == pid {
                    count += 1
                    let res = Golf.result(e, c), st = Golf.fit(e.strokes, c.holes)
                    birdies += st.enumerated().filter { $0.element > 0 && $0.element - c.pars[$0.offset] == -1 }.count
                    guard c.holes == 18 else { continue }
                    let g = res.complete ? res.gross : nil
                    r18.append((res.pts, g, c.name, r.day))
                    if let g, bestG == nil || g < bestG!.value { bestG = Best(value: g, pid: pid, course: c.name, day: r.day) }
                    if bestP == nil || res.pts > bestP!.value { bestP = Best(value: res.pts, pid: pid, course: c.name, day: r.day) }
                }
            }
            let half = r18.count / 2
            let g18 = r18.compactMap { x in x.gross.map { (g: $0, course: x.course, day: x.day) } }
            let bg = g18.min { $0.g < $1.g }
            let bp = r18.max { $0.pts < $1.pts }
            let pb = playerBadges(pid, y).states
            devils += pb["666"]?.count ?? 0
            let earned = BadgeDef.all.compactMap { b -> (badge: BadgeDef, count: Int, isNew: Bool)? in
                guard let s = pb[b.id], s.count > 0 else { return nil }
                var isNew = false
                if case .year(let v) = y, let fe = s.firstEver { isNew = Day.year(fe) == v }
                return (b, s.count, isNew)
            }
            players.append(SeasonPlayer(
                pid: pid, name: name(pid), rounds: count,
                avgPts: r18.map(\.pts).average, avgGross: g18.map(\.g).average,
                bestGross: bg.map { Best(value: $0.g, pid: pid, course: $0.course, day: $0.day) },
                bestPts: bp.map { Best(value: $0.pts, pid: pid, course: $0.course, day: $0.day) },
                firstHalf: half >= 2 ? Array(r18.prefix(half)).map(\.pts).average : nil,
                secondHalf: half >= 2 ? Array(r18.suffix(from: half)).map(\.pts).average : nil,
                hiStart: Golf.hiFromDiffs(Array(playerDiffs(pid, before: start).suffix(20))),
                hiEnd: Golf.hiFromDiffs(Array(playerDiffs(pid, before: next).suffix(20))),
                earned: earned))
        }
        players.sort { ($0.avgPts ?? 0) > ($1.avgPts ?? 0) }
        return Season(filter: y, rounds: rs, courses: Set(rs.compactMap(\.courseID)).count, players: players,
                      bestG: bestG, bestP: bestP, birdies: birdies, devils: devils, merit: merit(y, virt: false))
    }
}
