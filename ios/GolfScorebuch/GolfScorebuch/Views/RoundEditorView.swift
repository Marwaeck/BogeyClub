import SwiftUI
import SwiftData
import PhotosUI
import VisionKit

/// Runde erfassen oder bearbeiten – manuell, per Foto (offline) oder per TAG-Heuer-Link
struct RoundEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(sort: \Player.name) private var players: [Player]

    let round: Round?
    var startWithLink = false

    @State private var date = Date()
    @State private var course: Course?
    @State private var drafts: [EntryDraft] = []
    @State private var loaded = false

    @State private var showScanner = false
    @State private var showLink = false
    @State private var photoItem: PhotosPickerItem?
    @State private var scanImage: UIImage?
    @State private var importRows: [ScannedRow] = []
    @State private var importInfo: String?
    @State private var linkImport: LinkImport?
    @State private var showMapping = false
    @State private var busy = false
    @State private var message: String?
    @State private var source = ""
    @State private var confirmDelete = false

    private var holes: Int { course?.pars.count ?? 18 }
    private var pars: [Int] { course?.pars ?? Array(repeating: 4, count: 18) }

    private var receivedRows: [[Int]] {
        guard let c = course else { return [] }
        let cv = CourseV(id: c.uid, name: c.name, cr: c.courseRating, slope: c.slope, pars: c.pars, si: c.strokeIndex)
        return drafts.map { d in
            Golf.result(EntryV(playerID: d.player.uid, hcp: d.hcp, strokes: d.strokes, teeCR: d.teeRating, teeSlope: d.teeSlope), cv).rec
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Runde") {
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                    Picker("Platz", selection: $course) {
                        Text("Bitte wählen").tag(Course?.none)
                        ForEach(courses) { Text($0.name).tag(Optional($0)) }
                    }
                }

                Section {
                    if VNDocumentCameraViewController.isSupported {
                        Button { showScanner = true } label: { Label("Scorekarte fotografieren", systemImage: "doc.viewfinder") }
                    }
                    PhotosPicker(selection: $photoItem, matching: .images) { Label("Foto aus Mediathek", systemImage: "photo") }
                    Button { showLink = true } label: { Label("TAG-Heuer-Link einfügen", systemImage: "link") }
                    if busy { HStack { ProgressView(); Text("Wird gelesen …") } }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Einlesen") } footer: {
                    Text("Foto-Erkennung läuft offline auf dem iPhone. Prüfe die Werte danach in der Karte.")
                }

                Section("Spieler") {
                    ForEach(players) { p in
                        Button { toggle(p) } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if drafts.contains(where: { $0.player == p }) { Image(systemName: "checkmark").foregroundStyle(Color.fairway) }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if players.isEmpty { Text("Lege Spieler unter „Mehr › Spieler“ an oder übernimm sie beim Einlesen.").font(.footnote).foregroundStyle(.secondary) }
                }

                if !drafts.isEmpty {
                    Section {
                        ForEach($drafts) { $d in
                            VStack(alignment: .leading, spacing: 6) {
                                LabeledContent(d.player.name) {
                                    TextField("HCP", value: $d.hcp, format: .number.precision(.fractionLength(1)))
                                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                                }
                                if d.teeRating != nil {
                                    HStack {
                                        Text("Eigener Abschlag \(d.teeName ?? "")").font(.caption).foregroundStyle(.secondary)
                                        Spacer()
                                        Text("CR \(Fmt.one(d.teeRating)) / \(d.teeSlope ?? 0)").font(.caption.monospacedDigit())
                                        Button("Entfernen") { d.teeRating = nil; d.teeSlope = nil; d.teeName = nil }.font(.caption)
                                    }
                                }
                            }
                        }
                    } header: { Text("Handicap-Index am Spieltag") } footer: {
                        if course != nil { Text(playingHandicapText) }
                    }

                    Section {
                        ScoreGridView(pars: pars, received: receivedRows, drafts: $drafts)
                            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        SymbolLegend()
                    } header: { Text("Scorekarte") }

                    if let c = course {
                        let cv = CourseV(id: c.uid, name: c.name, cr: c.courseRating, slope: c.slope, pars: c.pars, si: c.strokeIndex)
                        Section("Ergebnis") {
                            ForEach(drafts) { d in
                                let r = Golf.result(EntryV(playerID: d.player.uid, hcp: d.hcp, strokes: d.strokes, teeCR: d.teeRating, teeSlope: d.teeSlope), cv)
                                HStack {
                                    Text(d.player.name)
                                    Spacer()
                                    Text("\(r.gross)\(r.complete ? "" : "*") (\(Fmt.vs(r.vsPar)))").monospacedDigit()
                                    Text("\(r.pts) P.").bold().monospacedDigit().frame(minWidth: 50, alignment: .trailing)
                                }
                            }
                        }
                    }
                }

                if round != nil {
                    Section { Button("Runde löschen", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(round == nil ? "Neue Runde" : "Runde bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.disabled(course == nil || drafts.isEmpty) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fertig") { hideKeyboard() } }
            }
            .confirmationDialog("Diese Runde wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let round { context.delete(round) }; dismiss() }
            }
            .onAppear(perform: load)
            .onChange(of: course) { resize() }
            .onChange(of: photoItem) {
                guard let item = photoItem else { return }
                Task {
                    if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { await scan(img) }
                    photoItem = nil
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView { img in
                    showScanner = false
                    if let img { Task { await scan(img) } }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showLink) {
                LinkImportView { imp in
                    linkImport = imp
                    importRows = imp.rows
                    scanImage = nil
                    var parts: [String] = []
                    if let n = imp.courseName { parts.append("Platz: \(n)") }
                    if let d = imp.date { parts.append("Datum: \(Fmt.date(d))") }
                    if let r = imp.rating, let s = imp.slope { parts.append("CR \(Fmt.one(r)) / Slope \(s)") }
                    importInfo = parts.joined(separator: " · ")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { showMapping = true }
                }
            }
            .sheet(isPresented: $showMapping) {
                ImportMappingView(rows: importRows, players: players, image: scanImage, info: importInfo, onApply: apply)
            }
            .task { if startWithLink && round == nil { showLink = true } }
        }
    }

    // MARK: - Logik

    private var courseV: CourseV? {
        guard let c = course else { return nil }
        return CourseV(id: c.uid, name: c.name, cr: c.courseRating, slope: c.slope, pars: c.pars, si: c.strokeIndex)
    }

    private var playingHandicapText: String {
        guard let cv = courseV else { return "" }
        return drafts.map { d in
            let e = EntryV(playerID: d.player.uid, hcp: d.hcp, strokes: [], teeCR: d.teeRating, teeSlope: d.teeSlope)
            return "\(d.player.name): Spielvorgabe \(Golf.courseHcp(d.hcp, Golf.tee(e, cv)))"
        }.joined(separator: " · ")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let round else { return }
        date = round.date
        course = round.course
        source = round.source
        drafts = round.entries.compactMap { e in
            guard let p = e.player else { return nil }
            return EntryDraft(player: p, hcp: e.handicapIndexAtRound, strokes: e.strokes, teeName: e.teeName, teeRating: e.teeRating, teeSlope: e.teeSlope)
        }
        .sorted { $0.player.name < $1.player.name }
        if let d = round.scanImage { scanImage = UIImage(data: d) }
    }

    private func toggle(_ p: Player) {
        if let i = drafts.firstIndex(where: { $0.player == p }) { drafts.remove(at: i) }
        else { drafts.append(EntryDraft(player: p, hcp: p.handicapIndex, strokes: Array(repeating: 0, count: holes))) }
    }

    private func resize() {
        for i in drafts.indices { drafts[i].strokes = Golf.fit(drafts[i].strokes, holes) }
    }

    @MainActor
    private func scan(_ image: UIImage) async {
        busy = true; message = nil
        defer { busy = false }
        scanImage = image
        linkImport = nil
        do {
            let rows = try await ScorecardScanner.scan(image)
            if rows.isEmpty {
                message = "Keine Zahlenzeilen erkannt. Karte flach, gut beleuchtet und formatfüllend fotografieren."
            } else {
                importRows = rows; importInfo = nil; showMapping = true
            }
        } catch {
            message = "Erkennung fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func apply(_ result: [(ScannedRow, RowAssignment)]) {
        let parRow = result.first { $0.1 == .par }?.0
        let siRow = result.first { $0.1 == .strokeIndex }?.0
        let n = parRow?.numbers.count ?? result.first { if case .player = $0.1 { return true }; if case .newPlayer = $0.1 { return true }; return false }?.0.numbers.count ?? holes

        // Platz: vorhandenen aktualisieren oder neu anlegen
        if course == nil, let parRow {
            let pars = parRow.numbers.map { (3...6).contains($0) ? $0 : 4 }
            let c = Course(name: linkImport?.courseName ?? "Neuer Platz",
                           courseRating: linkImport?.rating ?? Double(pars.sum),
                           slope: linkImport?.slope ?? 113,
                           pars: pars,
                           strokeIndex: siRow?.numbers.count == pars.count ? siRow!.numbers : Array(1...pars.count))
            context.insert(c)
            course = c
            message = linkImport?.rating == nil ? "Platz angelegt – bitte CR und Slope unter „Mehr › Plätze“ ergänzen." : "Platz „\(c.name)“ angelegt."
        } else if let c = course {
            if let parRow, parRow.numbers.count == c.pars.count { c.pars = parRow.numbers.map { (3...6).contains($0) ? $0 : 4 } }
            if let siRow, siRow.numbers.count == c.pars.count { c.strokeIndex = siRow.numbers }
        }
        if let d = linkImport?.date { date = d }
        let h = course?.pars.count ?? n

        for (row, a) in result {
            var player: Player?
            switch a {
            case .player(let id): player = players.first { $0.uid == id }
            case .newPlayer:
                let name = row.label.components(separatedBy: " · ").first?.trimmingCharacters(in: .whitespaces) ?? ""
                let p = Player(name: name.isEmpty ? "Neuer Spieler" : name)
                context.insert(p)
                player = p
            default: continue
            }
            guard let player else { continue }
            if let i = drafts.firstIndex(where: { $0.player == player }) {
                drafts[i].strokes = Golf.fit(row.numbers, h)
            } else {
                drafts.append(EntryDraft(player: player, hcp: player.handicapIndex, strokes: Golf.fit(row.numbers, h)))
            }
        }
        if linkImport != nil { source = "TAG Heuer" }
        let filled = result.filter { if case .player = $0.1 { return true }; if case .newPlayer = $0.1 { return true }; return false }.count
        message = (message.map { $0 + " " } ?? "") + "\(filled) Spielerzeile(n) übernommen – bitte in der Karte prüfen."
    }

    private func save() {
        let r = round ?? Round(date: date)
        if round == nil { context.insert(r) }
        r.date = date
        r.course = course
        r.updated = .now
        r.source = source
        if let scanImage, let d = scanImage.jpegData(compressionQuality: 0.6) { r.scanImage = d }
        for e in r.entries { context.delete(e) }
        for d in drafts {
            let e = PlayerRound(handicapIndexAtRound: d.hcp, strokes: Golf.fit(d.strokes, holes))
            e.teeName = d.teeName; e.teeRating = d.teeRating; e.teeSlope = d.teeSlope
            context.insert(e)
            e.player = d.player
            e.round = r
        }
        dismiss()
    }
}
