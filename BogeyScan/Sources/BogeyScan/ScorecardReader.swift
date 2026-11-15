import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Liest Scorekarten-Bilder komplett offline mit der Texterkennung von macOS (Apple Vision).
public enum ScorecardReader {

    /// Bilddaten (JPEG/PNG) → erkannte Wörter mit Positionen.
    public static func tokens(fromImageData data: Data) throws -> [OCRToken] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return [] }
        var orientation = CGImagePropertyOrientation.up
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let raw = props[kCGImagePropertyOrientation] as? UInt32,
           let o = CGImagePropertyOrientation(rawValue: raw) { orientation = o }
        return try tokens(from: image, orientation: orientation)
    }

    public static func tokens(from image: CGImage, orientation: CGImagePropertyOrientation = .up) throws -> [OCRToken] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
        var tokens = try recognize(handler, region: nil)

        // Zweiter Durchgang: leere Zellen einzeln nachlesen – einzeln stehende Ziffern werden
        // im Gesamtbild oft übersehen, im Ausschnitt aber zuverlässig erkannt.
        // Erst eng, dann mit Nachbarzellen als Kontext – das hilft der Erkennung bei einzelnen Ziffern.
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        for cell in ScorecardParser.missingCells(tokens).prefix(200) {
            for (fw, fh) in [(1.2, 2.4), (2.2, 4.0), (3.6, 3.0)] as [(CGFloat, CGFloat)] {
                let w = cell.spacing * fw, h = cell.height * fh
                let region = CGRect(x: cell.center.x - w / 2, y: cell.center.y - h / 2, width: w, height: h).intersection(unit)
                guard !region.isNull, region.width > 0, region.height > 0 else { continue }
                let found = (try? recognize(handler, region: region)) ?? []
                let near = found.filter { ScorecardParser.parseNumber($0.text) != nil && abs($0.box.midX - cell.center.x) < cell.spacing * 0.45 }
                if let best = near.min(by: { abs($0.box.midX - cell.center.x) < abs($1.box.midX - cell.center.x) }) {
                    tokens.append(best)
                    break
                }
            }
        }
        return tokens
    }

    /// Text erkennen, ganzes Bild oder nur ein Bereich (normiert); Positionen immer bezogen aufs ganze Bild.
    private static func recognize(_ handler: VNImageRequestHandler, region: CGRect?) throws -> [OCRToken] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["de-DE", "en-US"]
        if let region { request.regionOfInterest = region }
        try handler.perform([request])

        let roi = region ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        var out: [OCRToken] = []
        for obs in request.results ?? [] {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string
            // In einzelne Wörter zerlegen, damit „4 5 3“ drei Zellen ergibt
            for word in text.split(whereSeparator: { $0 == " " || $0 == "|" }) {
                let range = word.startIndex..<word.endIndex
                let b = (try? candidate.boundingBox(for: range))?.boundingBox ?? obs.boundingBox
                let box = CGRect(x: roi.minX + b.minX * roi.width, y: roi.minY + b.minY * roi.height,
                                 width: b.width * roi.width, height: b.height * roi.height)
                out.append(OCRToken(String(word), box))
            }
        }
        return out
    }

    /// Lädt die Texterkennung einmal vorab (beim App-Start im Hintergrund), damit das erste Einlesen
    /// einer Karte nicht auf das Laden des Erkennungsmodells warten muss.
    public static func warmUp() {
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        ctx?.setFillColor(gray: 1, alpha: 1); ctx?.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        if let image = ctx?.makeImage() { _ = try? recognize(VNImageRequestHandler(cgImage: image), region: nil) }
    }

    /// Mehrere Bilder (z. B. PDF-Seiten) lesen und zu einer Karte zusammenführen.
    public static func read(images: [Data]) throws -> ScanResult {
        let pages = try images.map { try tokens(fromImageData: $0) }
        return ScorecardParser.parse(pages: pages)
    }
}
