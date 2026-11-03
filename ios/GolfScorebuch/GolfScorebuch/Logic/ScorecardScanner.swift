import UIKit
import Vision

/// Eine erkannte Zeile der Scorekarte, z. B. "Par 4 5 3 4 ..." oder "Marcel 5 6 4 ...".
struct ScannedRow: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var numbers: [Int]
}

/// Liest Scorekarten komplett offline mit Apple Vision.
/// Vorgehen: Text mit Positionen erkennen → nach Höhe in Zeilen gruppieren → je Zeile
/// Beschriftung (Text) und Zahlen (von links nach rechts) trennen.
enum ScorecardScanner {

    static func scan(_ image: UIImage) async throws -> [ScannedRow] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["de-DE", "en-US"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            try handler.perform([request])
            return ScorecardScanner.buildRows(from: request.results ?? [])
        }.value
    }

    private struct Token {
        let text: String
        let box: CGRect
    }

    static func buildRows(from observations: [VNRecognizedTextObservation]) -> [ScannedRow] {
        // 1. In einzelne Wörter zerlegen, damit "4 5 3" drei Zellen ergibt
        var tokens: [Token] = []
        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            for word in text.split(whereSeparator: { $0 == " " || $0 == "|" || $0 == "/" }) {
                let range = word.startIndex..<word.endIndex
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                tokens.append(Token(text: String(word), box: box))
            }
        }
        guard !tokens.isEmpty else { return [] }

        // 2. Nach vertikaler Position gruppieren (Vision: Ursprung unten links)
        let heights = tokens.map(\.box.height).sorted()
        let tolerance = heights[heights.count / 2] * 0.6
        var groups: [[Token]] = []
        for token in tokens.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = groups.last {
                let ref = last.map(\.box.midY).reduce(0, +) / CGFloat(last.count)
                if abs(ref - token.box.midY) < tolerance {
                    groups[groups.count - 1].append(token)
                    continue
                }
            }
            groups.append([token])
        }

        // 3. Je Zeile Beschriftung und Zahlen trennen
        return groups.compactMap { group in
            var labelParts: [String] = []
            var numbers: [Int] = []
            for token in group.sorted(by: { $0.box.minX < $1.box.minX }) {
                if let n = parseNumber(token.text) {
                    if (1...20).contains(n) { numbers.append(n) }   // Summen (Out/In/Total) ignorieren
                } else {
                    labelParts.append(token.text)
                }
            }
            guard numbers.count >= 5 else { return nil }
            return ScannedRow(label: labelParts.joined(separator: " "), numbers: numbers)
        }
    }

    /// Erkennt Zahlen inkl. typischer OCR-Verwechslungen bei Handschrift (O→0, l→1, S→5 …).
    static func parseNumber(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;-–_()[]"))
        if let n = Int(trimmed) { return n }
        guard trimmed.count <= 2 else { return nil }
        let map: [Character: Character] = ["O": "0", "o": "0", "D": "0", "l": "1", "I": "1", "i": "1",
                                           "|": "1", "Z": "2", "z": "2", "S": "5", "s": "5",
                                           "G": "6", "b": "6", "T": "7", "B": "8", "g": "9", "q": "9"]
        let mapped = String(trimmed.map { map[$0] ?? $0 })
        return Int(mapped)
    }
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
