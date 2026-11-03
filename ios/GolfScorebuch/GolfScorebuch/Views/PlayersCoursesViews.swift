import SwiftUI
import SwiftData

struct PlayersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.name) private var players: [Player]
    @Query private var courses: [Course]
    @Query private var rounds: [Round]
    @State private var editing: Player?
    @State private var showNew = false

    var body: some View {
        let data = GolfData(players: players, courses: courses, rounds: rounds)
        List {
            ForEach(players) { p in
                Button { editing = p } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            Text("\(p.entries.count) Runden").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("HCP \(Fmt.one(p.handicapIndex))").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color(.secondarySystemBackground)))
                        let v = data.virtualHI(p.uid)
                        Text(v.hi.map { "virt. \(Fmt.one($0))" } ?? "virt. \(v.count)/3").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.fairway.opacity(0.15))).foregroundStyle(Color.fairway)
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { idx in idx.forEach { context.delete(players[$0]) } }
        }
        .overlay { if players.isEmpty { ContentUnavailableView("Keine Spieler", systemImage: "person.badge.plus", description: Text("Lege die Spieler deiner Runden an.")) } }
        .navigationTitle("Spieler")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { PlayerEditView(player: nil) }
        .sheet(item: $editing) { PlayerEditView(player: $0) }
    }
}

struct PlayerEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let player: Player?
    @State private var name = ""
    @State private var hcp = 54.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                LabeledContent("Offizieller Handicap-Index") {
                    TextField("HCP", value: $hcp, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
            }
            .navigationTitle(player == nil ? "Neuer Spieler" : "Spieler")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let n = name.trimmingCharacters(in: .whitespaces)
                        if let player { player.name = n; player.handicapIndex = hcp } else { context.insert(Player(name: n, handicapIndex: hcp)) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if let player { name = player.name; hcp = player.handicapIndex } }
        }
    }
}

struct CoursesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @State private var editing: Course?
    @State private var showNew = false

    var body: some View {
        List {
            ForEach(courses) { c in
                Button { editing = c } label: {
                    VStack(alignment: .leading) {
                        Text(c.name).font(.headline)
                        Text("\(c.pars.count) Loch · Par \(c.pars.sum) · CR \(Fmt.one(c.courseRating)) · Slope \(c.slope)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { idx in idx.forEach { context.delete(courses[$0]) } }
        }
        .overlay { if courses.isEmpty { ContentUnavailableView("Keine Plätze", systemImage: "map", description: Text("Lege Plätze mit Par, Lochvorgaben, CR und Slope an – oder übernimm sie beim Einlesen einer Runde.")) } }
        .navigationTitle("Plätze")
        .toolbar { Button { showNew = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $showNew) { CourseEditView(course: nil) }
        .sheet(item: $editing) { CourseEditView(course: $0) }
    }
}

struct CourseEditView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let course: Course?
    @State private var name = ""
    @State private var cr = 72.0
    @State private var slope = 113
    @State private var pars = Array(repeating: 4, count: 18)
    @State private var si = Array(1...18)

    private var holes: Binding<Int> {
        Binding(get: { pars.count }, set: { n in
            guard n != pars.count else { return }
            pars = Array(repeating: 4, count: n); si = Array(1...n)
        })
    }
    private func parB(_ i: Int) -> Binding<Int> { Binding(get: { i < pars.count ? pars[i] : 4 }, set: { if i < pars.count { pars[i] = $0 } }) }
    private func siB(_ i: Int) -> Binding<Int> { Binding(get: { i < si.count ? si[i] : 0 }, set: { if i < si.count { si[i] = $0 } }) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Platz") {
                    TextField("Name (inkl. Abschlag, z. B. „Bruchsal (Gelb)“)", text: $name)
                    LabeledContent("Course Rating") {
                        TextField("CR", value: $cr, format: .number.precision(.fractionLength(1))).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Slope") {
                        TextField("Slope", value: $slope, format: .number).keyboardType(.numberPad).multilineTextAlignment(.trailing)
                    }
                    Picker("Löcher", selection: holes) { Text("9").tag(9); Text("18").tag(18) }.pickerStyle(.segmented)
                }
                Section {
                    ForEach(0..<pars.count, id: \.self) { i in
                        HStack {
                            Text("Loch \(i + 1)").frame(width: 64, alignment: .leading)
                            Stepper("Par \(parB(i).wrappedValue)", value: parB(i), in: 3...6)
                            TextField("Vg", value: siB(i), format: .number).keyboardType(.numberPad)
                                .multilineTextAlignment(.center).textFieldStyle(.roundedBorder).frame(width: 50)
                        }
                    }
                } header: { Text("Par & Lochvorgabe") } footer: {
                    Text("Par gesamt: \(pars.sum). Bei 9-Loch-Plätzen CR und Slope für 9 Löcher eintragen.")
                }
            }
            .navigationTitle(course == nil ? "Neuer Platz" : "Platz")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Sichern") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fertig") { hideKeyboard() } }
            }
            .onAppear {
                if let c = course {
                    name = c.name; cr = c.courseRating; slope = c.slope; pars = c.pars
                    si = c.strokeIndex.count == c.pars.count ? c.strokeIndex : Array(1...max(1, c.pars.count))
                }
            }
        }
    }

    private func save() {
        let c = course ?? Course(name: name)
        if course == nil { context.insert(c) }
        c.name = name.trimmingCharacters(in: .whitespaces); c.courseRating = cr; c.slope = slope; c.pars = pars; c.strokeIndex = si
        dismiss()
    }
}

struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { ReviewView() } label: { Label("Saisonrückblick", systemImage: "calendar") }
                NavigationLink { PlayersView() } label: { Label("Spieler", systemImage: "person.2") }
                NavigationLink { CoursesView() } label: { Label("Plätze", systemImage: "map") }
            }
            .navigationTitle("Mehr")
        }
    }
}
