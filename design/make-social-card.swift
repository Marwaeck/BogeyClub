// Zeichnet das Vorschaubild für das GitHub-Repository („Social preview“, 1280 × 640) → design/social-card.png.
// Wichtiges bleibt innerhalb des empfohlenen Rands (80 px bei 1280 Breite), damit nichts abgeschnitten wird.
// Aufruf aus dem Projektordner (nach mac/icon/make-icon.swift, das das Logo zeichnet):
//   swift design/make-social-card.swift
// Hochladen: GitHub → Repository → Settings → General → Social preview → Edit → Upload an image.
import AppKit

let W = 1280, H = 640, SAFE: CGFloat = 80
let G1 = NSColor(srgbRed: 12/255, green: 60/255, blue: 37/255, alpha: 1)
let G2 = NSColor(srgbRed: 34/255, green: 118/255, blue: 74/255, alpha: 1)
let CREAM = NSColor(srgbRed: 248/255, green: 244/255, blue: 232/255, alpha: 1)
let GOLD = NSColor(srgbRed: 222/255, green: 174/255, blue: 46/255, alpha: 1)

/// Schriften der App (mac/vendor/fonts), sonst Systemschriften.
func appFont(_ file: String, _ size: CGFloat, fallback: NSFont) -> NSFont {
    let url = URL(fileURLWithPath: "mac/vendor/fonts/\(file)")
    guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let d = descs.first,
          let name = CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String else { return fallback }
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    return NSFont(name: name, size: size) ?? fallback
}
let title = appFont("BarlowCondensed-700-latin.woff2", 168, fallback: .systemFont(ofSize: 150, weight: .heavy))
let label = appFont("BarlowCondensed-600-latin.woff2", 30, fallback: .systemFont(ofSize: 28, weight: .semibold))
let body = appFont("PublicSans-500-latin.woff2", 34, fallback: .systemFont(ofSize: 32, weight: .medium))

func draw(_ s: String, _ f: NSFont, _ c: NSColor, at p: NSPoint, kern: CGFloat = 0) -> NSSize {
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c, .kern: kern])
    a.draw(at: p)
    return a.size()
}

let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let full = NSRect(x: 0, y: 0, width: W, height: H)

// Hintergrund: Grün mit Mähstreifen wie im Icon
NSGradient(starting: G2, ending: G1)!.draw(in: full, angle: -60)
NSColor.white.withAlphaComponent(0.04).setFill()
for i in stride(from: -6, to: 14, by: 2) {
    let x = CGFloat(i) * 110, p = NSBezierPath()
    p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x + 110, y: 0))
    p.line(to: NSPoint(x: x + 110 + CGFloat(H), y: CGFloat(H))); p.line(to: NSPoint(x: x + CGFloat(H), y: CGFloat(H))); p.close(); p.fill()
}

// Logo links
let logoSide: CGFloat = 370
let logoRect = NSRect(x: SAFE + 10, y: (CGFloat(H) - logoSide) / 2, width: logoSide, height: logoSide)
if let logo = NSImage(contentsOfFile: "web/bogey-club-logo.png") {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowBlurRadius = 30; sh.shadowOffset = NSSize(width: 0, height: -14)
    sh.shadowColor = NSColor.black.withAlphaComponent(0.45); sh.set()
    logo.draw(in: logoRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
}

// Text rechts
let x = logoRect.maxX + 56
// Titel so groß wie möglich, aber innerhalb des Rands
var titleFont = title
while NSAttributedString(string: "BOGEY CLUB", attributes: [.font: titleFont, .kern: 1]).size().width > CGFloat(W) - SAFE - x {
    titleFont = NSFont(descriptor: titleFont.fontDescriptor, size: titleFont.pointSize - 2) ?? titleFont
}
_ = draw("PRIVATES GOLF-SCOREBUCH", label, GOLD, at: NSPoint(x: x + 4, y: 430), kern: 3)
_ = draw("BOGEY CLUB", titleFont, CREAM, at: NSPoint(x: x, y: 262), kern: 1)
_ = draw("Scorekarten sammeln,", body, CREAM.withAlphaComponent(0.9), at: NSPoint(x: x + 4, y: 210))
_ = draw("Saison auswerten, Bogeys feiern.", body, CREAM.withAlphaComponent(0.9), at: NSPoint(x: x + 4, y: 166))

// Plattformen als Marken
var cx = x + 4
for name in ["Web-App", "iPhone", "Mac"] {
    let a = NSAttributedString(string: name, attributes: [.font: label, .foregroundColor: CREAM, .kern: 1])
    let size = a.size()
    let chip = NSRect(x: cx, y: SAFE + 6, width: size.width + 36, height: 50)
    let path = NSBezierPath(roundedRect: chip, xRadius: 25, yRadius: 25)
    NSColor.white.withAlphaComponent(0.08).setFill(); path.fill()
    GOLD.setStroke(); path.lineWidth = 2.5; path.stroke()
    a.draw(at: NSPoint(x: chip.minX + 18, y: chip.midY - size.height / 2))
    cx = chip.maxX + 14
}

NSGraphicsContext.current = nil
let png = NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "design/social-card.png"))
print("design/social-card.png erstellt (\(png.count / 1024) KB)")
