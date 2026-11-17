import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BogeyScan

/// Öffnet .bogey-Dateien (aus Dateien, Mail, WhatsApp, „Datei einspielen …“) und zeigt vor dem Einspielen eine Vorschau.
@Observable
final class BogeyOpener {
    var plan: BogeyTransfer.Plan?
    var error: String?

    func open(_ url: URL, context: ModelContext) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let (doc, _) = try BogeyFile.decode(data)
            plan = try BogeyTransfer.plan(doc, context: context)
        } catch {
            self.error = BogeyTransfer.message(for: error)
        }
    }
}

extension BogeyTransfer.Plan: Identifiable {
    var id: String { (document.exportedAt ?? "") + title }
}

struct BogeyImportSheet: View {
    let plan: BogeyTransfer.Plan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var done: String?
    @State private var failed: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(plan.title, systemImage: plan.kind == .round ? "flag.fill" : "externaldrive.fill").font(.headline)
                    ForEach(plan.details, id: \.self) { Text($0).font(.subheadline) }
                }
                if let done { Section { Label(done, systemImage: "checkmark.circle.fill").foregroundStyle(Color.fairway) } }
                if let failed { Section { Text(failed).foregroundStyle(.red) } }
            }
            .navigationTitle(plan.kind == .round ? "Runde übernehmen" : "Backup einspielen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(done == nil ? "Abbrechen" : "Fertig") { dismiss() } }
                if done == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(plan.kind == .round ? "Übernehmen" : "Einspielen") {
                            do {
                                try BogeyTransfer.apply(plan, context: context)
                                done = plan.kind == .round ? "Runde übernommen – du findest sie unter „Runden“." : "Backup eingespielt."
                            } catch { failed = "Das Einspielen hat nicht geklappt: \(error.localizedDescription)" }
                        }
                    }
                }
            }
        }
    }
}

/// Mehr → Daten-Backup
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(BogeyOpener.self) private var opener
    @Query private var players: [Player]
    @Query private var courses: [Course]
    @Query private var rounds: [Round]
    @State private var fileURL: URL?
    @State private var error: String?
    @State private var showImporter = false

    var body: some View {
        List {
            Section {
                Text("Sichert alle Spieler, Plätze und Runden in einer Bogey-Datei (.bogey). Sie lässt sich in jeder Bogey-Club-App öffnen – iPhone, Mac, Windows, Android und Web-App.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { makeBackup() } label: { Label("Backup erstellen", systemImage: "externaldrive.badge.plus") }
                if let fileURL {
                    ShareLink(item: fileURL) { Label("Backup teilen oder in Dateien sichern", systemImage: "square.and.arrow.up") }
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            } header: { Text("Sichern") } footer: { Text("\(players.count) Spieler · \(courses.count) Plätze · \(rounds.count) Runden") }
            Section {
                Button { showImporter = true } label: { Label("Datei einspielen …", systemImage: "square.and.arrow.down") }
            } header: { Text("Einspielen") } footer: {
                Text("Bogey-Dateien und Backups der anderen Apps. Einträge mit gleicher ID werden aktualisiert, Spieler und Plätze sonst über den Namen zugeordnet. Gelöscht wird nichts. Eine .bogey-Datei kannst du auch einfach in Dateien, Mail oder WhatsApp antippen.")
            }
        }
        .navigationTitle("Daten-Backup")
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.bogey, .json, .zip, .data]) { result in
            if case .success(let url) = result { opener.open(url, context: context) }
        }
    }

    private func makeBackup() {
        do { fileURL = try BogeyTransfer.backupFile(players: players, courses: courses, rounds: rounds); error = nil }
        catch { self.error = "Das Backup konnte nicht erstellt werden." }
    }
}

/// Teilen-Menü des Systems für eine fertige Datei (Runde als .bogey an Freunde)
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct SharedFile: Identifiable {
    let url: URL
    var id: String { url.path }
}
