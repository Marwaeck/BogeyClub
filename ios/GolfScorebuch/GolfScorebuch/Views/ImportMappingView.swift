import SwiftUI
import VisionKit

enum RowAssignment: Hashable {
    case ignore, par, strokeIndex, newPlayer
    case player(UUID)
}

/// Erkannte Zeilen (Foto oder Link) Spielern, Par oder Lochvorgabe zuordnen
struct ImportMappingView: View {
    let rows: [ScannedRow]
    let players: [Player]
    let image: UIImage?
    var info: String?
    var onApply: ([(ScannedRow, RowAssignment)]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assignments: [UUID: RowAssignment] = [:]

    var body: some View {
        NavigationStack {
            List {
                if let image {
                    Section { Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 8)) }
                }
                if let info { Section { Text(info).font(.callout) } }
                Section {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.label.isEmpty ? "Zeile ohne Beschriftung" : row.label).font(.headline)
                            Text(row.numbers.map { $0 == 0 ? "–" : String($0) }.joined(separator: " "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            Picker("Zuordnung", selection: binding(row)) {
                                Text("Ignorieren").tag(RowAssignment.ignore)
                                ForEach(players) { p in Text(p.name).tag(RowAssignment.player(p.uid)) }
                                Text("Neuer Spieler").tag(RowAssignment.newPlayer)
                                Text("Par des Platzes").tag(RowAssignment.par)
                                Text("Lochvorgaben des Platzes").tag(RowAssignment.strokeIndex)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: { Text("Erkannte Zeilen (\(rows.count))") } footer: {
                    Text("Ordne die Schlagzeilen den Spielern zu. Zeilen wie Putts, Vorgabeschläge oder Punkte bitte ignorieren. Einzelne Werte kannst du danach in der Karte korrigieren.")
                }
            }
            .navigationTitle("Werte zuordnen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { onApply(rows.map { ($0, assignments[$0.id] ?? .ignore) }); dismiss() }
                }
            }
            .onAppear(perform: guess)
        }
    }

    private func binding(_ row: ScannedRow) -> Binding<RowAssignment> {
        Binding(get: { assignments[row.id] ?? .ignore }, set: { assignments[row.id] = $0 })
    }

    /// Vorschlag anhand der Beschriftung
    private func guess() {
        guard assignments.isEmpty else { return }
        var used = Set<UUID>()
        var hasPar = false, hasSI = false
        for row in rows {
            let l = row.label.lowercased()
            let isStrokeRow = ["score", "schläge", "strokes", "brutto", "gross"].contains { l.contains($0) } || !["putt", "hcp", "stableford", "punkte", "net", "vorgabe", "par", "index", "si", "loch", "hole"].contains { l.contains($0) }
            if !hasPar && (l == "par" || l.hasPrefix("par ") || l.hasSuffix(" par") || l.contains("· par")) && row.numbers.allSatisfy({ (3...6).contains($0) }) {
                assignments[row.id] = .par; hasPar = true; continue
            }
            if !hasSI && ["handicap", "hcp", "si", "index", "vorgabe"].contains(where: { l.contains($0) }) && Set(row.numbers).count == row.numbers.count && (row.numbers.max() ?? 0) > 6 {
                assignments[row.id] = .strokeIndex; hasSI = true; continue
            }
            guard isStrokeRow else { continue }
            if let p = players.first(where: { p in !used.contains(p.uid) && matches(l, p.name.lowercased()) }) {
                assignments[row.id] = .player(p.uid); used.insert(p.uid)
            }
        }
    }

    private func matches(_ label: String, _ name: String) -> Bool {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return label.contains(first) || (first.count >= 3 && label.contains(first.prefix(3)))
    }
}

/// VisionKit-Dokumentenscanner
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let c = VNDocumentCameraViewController(); c.delegate = context.coordinator; return c
    }
    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish(scan.pageCount > 0 ? scan.imageOfPage(at: 0) : nil)
        }
        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { onFinish(nil) }
        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish(nil) }
    }
}
