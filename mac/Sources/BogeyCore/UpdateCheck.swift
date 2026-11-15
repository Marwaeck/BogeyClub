import Foundation

/// Neueste Version auf GitHub (Releases von Marwaeck/BogeyClub) auswerten – ohne Netzwerk, damit testbar.
/// Erwartet ein Release mit Tag „v1.2.3“ und einer ZIP-Datei, deren Name mit dem Präfix beginnt
/// (Mac: „Bogey-Club-mac-“, Windows: „Bogey-Club-windows-“).
public struct Release: Equatable {
    public var version: String
    public var notes: String
    public var pageURL: URL
    public var assetURL: URL?
    public var assetSize: Int
}

public enum UpdateCheck {
    public static let repository = "Marwaeck/BogeyClub"
    public static var latestURL: URL { URL(string: "https://api.github.com/repos/\(repository)/releases/latest")! }
    public static var releasesPage: URL { URL(string: "https://github.com/\(repository)/releases")! }

    public enum Failure: Error { case badData }

    public static func parse(_ data: Data, assetPrefix: String) throws -> Release {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let page = (obj["html_url"] as? String).flatMap(URL.init(string:)) else { throw Failure.badData }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let assets = obj["assets"] as? [[String: Any]] ?? []
        let asset = assets.first { ($0["name"] as? String).map { $0.hasPrefix(assetPrefix) && $0.lowercased().hasSuffix(".zip") } ?? false }
        return Release(version: version,
                       notes: (obj["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                       pageURL: page,
                       assetURL: (asset?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                       assetSize: asset?["size"] as? Int ?? 0)
    }

    /// Versionen wie „1.10.0“ zahlenweise vergleichen (fehlende Stellen = 0, Zusätze nach „-“ ignoriert).
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let parts = { (v: String) -> [Int] in
            v.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
