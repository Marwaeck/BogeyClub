import UIKit
import ImageIO
import BogeyScan

/// Eine erkannte Zeile der Scorekarte, z. B. "Par 4 5 3 4 ..." oder "Marcel 5 6 4 ...".
struct ScannedRow: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var numbers: [Int]
}

/// Liest Scorekarten komplett offline mit Apple Vision – über das gemeinsame Paket BogeyScan,
/// das auch die Mac-App nutzt. Lochnummern dienen als Spaltenraster (leere Felder = 0,
/// Summenspalten fallen weg), einzeln übersehene Ziffern werden gezielt nachgelesen.
enum ScorecardScanner {

    struct Result {
        var rows: [ScannedRow]
        /// Kurzinfo für die Zuordnung, z. B. „Platz „GC Bruchsal“ · 14.09.2026“
        var info: String?
    }

    static func scan(_ image: UIImage) async throws -> Result {
        guard let cgImage = image.cgImage else { return Result(rows: [], info: nil) }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        let scan = try await Task.detached(priority: .userInitiated) {
            ScorecardParser.parse(pages: [try ScorecardReader.tokens(from: cgImage, orientation: orientation)])
        }.value

        var rows: [ScannedRow] = []
        if !scan.par.isEmpty { rows.append(ScannedRow(label: "Par", numbers: scan.par)) }
        if !scan.strokeIndex.isEmpty { rows.append(ScannedRow(label: "Hcp", numbers: scan.strokeIndex)) }
        rows += scan.players.map { ScannedRow(label: $0.name, numbers: $0.strokes) }

        var info: [String] = []
        if let c = scan.course { info.append("Platz „\(c)“") }
        if let d = scan.date, let date = ISO8601DateFormatter.dateOnly.date(from: d) {
            info.append(date.formatted(date: .numeric, time: .omitted))
        }
        return Result(rows: rows, info: info.isEmpty ? nil : info.joined(separator: " · "))
    }
}

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]; return f
    }()
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
