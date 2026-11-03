import Foundation

/// Golf-Rechenregeln (WHS / DGV) – identisch zur Web-App.
enum Golf {

    /// JS-kompatibles Runden (x.5 rundet nach oben)
    static func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

    static func fit(_ a: [Int], _ n: Int) -> [Int] {
        var r = a.prefix(n).map { max(0, min(20, $0)) }
        while r.count < n { r.append(0) }
        return r
    }

    /// Spielvorgabe: HCP-Index × Slope/113 + (CR − Par); 9-Loch-Platz mit halbem Index
    static func courseHcp(_ hi: Double, _ c: CourseV) -> Int {
        let n = c.pars.count, par = Double(c.par)
        let h = n <= 9 ? hi / 2 : hi
        return jsRound(h * Double(c.slope > 0 ? c.slope : 113) / 113 + (c.cr - par))
    }

    /// Lochvorgaben in Ränge 1...n umwandeln (robust bei 9-Loch-Karten mit 1–18)
    static func ranks(_ si: [Int], _ n: Int) -> [Int] {
        let v = (0..<n).map { i in (i < si.count && si[i] > 0) ? si[i] : 100 + i }
        let order = v.indices.sorted { v[$0] != v[$1] ? v[$0] < v[$1] : $0 < $1 }
        var r = Array(repeating: 0, count: n)
        for (k, idx) in order.enumerated() { r[idx] = k + 1 }
        return r
    }

    static func received(rank: Int, ph: Int, n: Int) -> Int {
        guard n > 0 else { return 0 }
        if ph >= 0 { return ph / n + ((ph % n) >= rank ? 1 : 0) }
        let p = -ph
        return -(p / n + (rank > n - (p % n) ? 1 : 0))
    }

    /// Eigener Abschlag eines Spielers überschreibt CR/Slope
    static func tee(_ e: EntryV, _ c: CourseV) -> CourseV {
        guard let cr = e.teeCR, let sl = e.teeSlope else { return c }
        var t = c; t.cr = cr; t.slope = sl; return t
    }

    struct Result {
        var gross = 0, played = 0, n = 0, vsPar = 0, ph = 0, net = 0, pts = 0
        var rec: [Int] = [], hp: [Int] = []
        var complete: Bool { played == n }
    }

    static func result(_ e: EntryV, _ c: CourseV) -> Result {
        let n = c.pars.count, rk = ranks(c.si, n), ph = courseHcp(e.hcp, tee(e, c)), st = fit(e.strokes, n)
        var r = Result(); r.n = n; r.ph = ph
        var parP = 0
        for i in 0..<n {
            let s = st[i], rec = received(rank: rk[i], ph: ph, n: n)
            r.rec.append(rec)
            let p = s > 0 ? max(0, 2 + c.pars[i] + rec - s) : 0
            r.hp.append(p); r.pts += p
            if s > 0 { r.gross += s; parP += c.pars[i]; r.played += 1 }
        }
        r.vsPar = r.gross - parP
        r.net = r.gross - ph
        return r
    }

    // MARK: Score-Differentials

    /// 18-Loch-Differential (ab 14 gespielten Löchern), Netto-Doppelbogey als Obergrenze
    static func scoreDifferential(_ e: EntryV, _ c: CourseV) -> Double? {
        let n = c.pars.count
        guard n == 18 else { return nil }
        let st = fit(e.strokes, n)
        guard st.filter({ $0 > 0 }).count >= 14 else { return nil }
        let t = tee(e, c), rk = ranks(c.si, n), ph = courseHcp(e.hcp, t)
        var ags = 0
        for i in 0..<n {
            let cap = c.pars[i] + 2 + received(rank: rk[i], ph: ph, n: n)
            ags += st[i] > 0 ? min(st[i], cap) : cap
        }
        return 113 / Double(t.slope > 0 ? t.slope : 113) * (Double(ags) - t.cr)
    }

    /// 9-Loch-Differential: 9-Loch-Platz oder nur vordere/hintere Hälfte gespielt
    static func nineHoleDiff(_ e: EntryV, _ c: CourseV) -> Double? {
        let n = c.pars.count, st = fit(e.strokes, n), t = tee(e, c)
        var idx: [Int]
        var cr: Double
        if n == 9 {
            idx = Array(0..<9); cr = t.cr
        } else if n == 18 {
            let front = st[0..<9].filter { $0 > 0 }.count, back = st[9..<18].filter { $0 > 0 }.count
            if front >= 7 && back == 0 { idx = Array(0..<9) }
            else if back >= 7 && front == 0 { idx = Array(9..<18) }
            else { return nil }
            cr = t.cr / 2   // Näherung: halbes Course Rating
        } else { return nil }
        guard idx.filter({ st[$0] > 0 }).count >= 7 else { return nil }
        let slope = t.slope > 0 ? t.slope : 113
        let sub = CourseV(id: c.id, name: c.name, cr: cr, slope: slope, pars: idx.map { c.pars[$0] }, si: idx.map { $0 < c.si.count ? c.si[$0] : 0 })
        let rk = ranks(sub.si, 9), ph = courseHcp(e.hcp, sub)
        var ags = 0
        for (k, i) in idx.enumerated() {
            let cap = sub.pars[k] + 2 + received(rank: rk[k], ph: ph, n: 9)
            ags += st[i] > 0 ? min(st[i], cap) : cap
        }
        return 113 / Double(slope) * (Double(ags) - cr)
    }

    /// Erwartetes 9-Loch-Differential (WHS 2024)
    static func expected9(_ hi: Double) -> Double { 0.52 * max(0, hi) + 1.2 }

    /// WHS-Tabelle: beste n der letzten 20 plus Korrektur
    static func hiFromDiffs(_ d: [Double]) -> Double? {
        let n = d.count
        guard n >= 3 else { return nil }
        let s = d.sorted()
        let (k, adj): (Int, Double) = {
            switch n {
            case 3: return (1, -2)
            case 4: return (1, -1)
            case 5: return (1, 0)
            case 6: return (2, -1)
            case 7...8: return (2, 0)
            case 9...11: return (3, 0)
            case 12...14: return (4, 0)
            case 15...16: return (5, 0)
            case 17...18: return (6, 0)
            case 19: return (7, 0)
            default: return (8, 0)
            }
        }()
        let v = s.prefix(k).reduce(0, +) / Double(k) + adj
        return max(-10, min(54, floor(v * 10 + 0.5) / 10))
    }
}

extension Array where Element == Int {
    var sum: Int { reduce(0, +) }
    var average: Double? { isEmpty ? nil : Double(reduce(0, +)) / Double(count) }
}
extension Array where Element == Double {
    var average: Double? { isEmpty ? nil : reduce(0, +) / Double(count) }
}
