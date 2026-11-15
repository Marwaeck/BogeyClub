// Zeichnet das Programm-Icon von Bogey Club (Vektor, Club-Farben und Schrift der App) für alle Plattformen:
//   • Mac-App:   mac/build/AppIcon.iconset → mac/AppIcon.icns (abgerundetes Quadrat im macOS-Stil, mit Rand)
//   • iPhone:    ios/GolfScorebuch/GolfScorebuch/Assets.xcassets/AppIcon.appiconset/icon.png (1024, randlos)
//   • Web-App:   server/icons/icon-192.png, icon-512.png, apple-touch-icon.png (randlos)
//   • Logo:      web/bogey-club-logo.png (Kopf der App und PDF-Ausdrucke; abgerundet, transparenter Rand)
// Aufruf aus dem Projektordner:
//   swift mac/icon/make-icon.swift && iconutil -c icns mac/build/AppIcon.iconset -o mac/AppIcon.icns
// Motiv: Scorekarte mit dem Bogey-Kästchen „5“, Bleistift und Golfball auf Grün.
// Kleine Größen (unter 64 px) bekommen eine vereinfachte Fassung ohne Raster und Ziffern.
import AppKit

let G1 = NSColor(srgbRed: 12/255, green: 60/255, blue: 37/255, alpha: 1)      // dunkelgrün
let G2 = NSColor(srgbRed: 34/255, green: 118/255, blue: 74/255, alpha: 1)     // hellgrün
let GD = NSColor(srgbRed: 18/255, green: 80/255, blue: 50/255, alpha: 1)      // Club-Grün
let CREAM = NSColor(srgbRed: 248/255, green: 244/255, blue: 232/255, alpha: 1)
let LINE = NSColor(srgbRed: 214/255, green: 226/255, blue: 216/255, alpha: 1)
let GOLD = NSColor(srgbRed: 222/255, green: 174/255, blue: 46/255, alpha: 1)
let GOLDL = NSColor(srgbRed: 240/255, green: 200/255, blue: 80/255, alpha: 1)
let GOLDD = NSColor(srgbRed: 176/255, green: 132/255, blue: 28/255, alpha: 1)
let WOOD = NSColor(srgbRed: 236/255, green: 208/255, blue: 156/255, alpha: 1)
let INK = NSColor(srgbRed: 26/255, green: 36/255, blue: 30/255, alpha: 1)
let STEEL = NSColor(srgbRed: 196/255, green: 203/255, blue: 208/255, alpha: 1)
let ROSE = NSColor(srgbRed: 214/255, green: 120/255, blue: 120/255, alpha: 1)

/// Barlow Condensed (die Schrift der App, liegt in mac/vendor/fonts); sonst eine schmale Systemschrift.
let barlow: String? = {
    let url = URL(fileURLWithPath: "mac/vendor/fonts/BarlowCondensed-700-latin.woff2")
    guard let descs = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let d = descs.first else { return nil }
    return CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String
}()

func font(_ size: CGFloat, _ weight: NSFont.Weight = .heavy) -> NSFont {
    if let name = barlow {
        let url = URL(fileURLWithPath: "mac/vendor/fonts/BarlowCondensed-700-latin.woff2")
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        if let f = NSFont(name: name, size: size) { return f }
    }
    return NSFont(name: "Futura-CondensedExtraBold", size: size) ?? NSFont.systemFont(ofSize: size, weight: weight)
}

func shadow(_ blur: CGFloat, _ y: CGFloat, _ alpha: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: -y)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha); s.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func rotated(_ angle: CGFloat, around p: NSPoint, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let t = NSAffineTransform(); t.translateX(by: p.x, yBy: p.y); t.rotate(byDegrees: angle); t.translateX(by: -p.x, yBy: -p.y); t.concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ s: String, _ f: NSFont, _ color: NSColor, center: NSPoint) {
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color])
    let size = a.size()
    a.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
}

/// Zeichnet das Icon auf einer 1024er-Fläche (Ursprung unten links).
/// `fullBleed`: randloses Quadrat (iPhone/Web runden die Ecken selbst ab) statt macOS-Kachel mit Rand.
func drawIcon(detail: Bool, fullBleed: Bool = false) {
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    // Randlos: Hintergrund füllt das ganze Bild, das Motiv bekommt etwas Luft zu den abgerundeten Ecken
    let k: CGFloat = fullBleed ? 1024 / 824 * 0.93 : 1
    if fullBleed {
        let t = NSAffineTransform(); t.translateX(by: 512, yBy: 512); t.scale(by: k); t.translateX(by: -512, yBy: -512); t.concat()
    }
    let bg = fullBleed ? tile.insetBy(dx: -(1024 / k - 824) / 2 - 1, dy: -(1024 / k - 824) / 2 - 1) : tile
    let tilePath = fullBleed ? NSBezierPath(rect: bg) : NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    // Grundplatte mit Schatten
    if fullBleed { GD.setFill(); tilePath.fill() } else { shadow(28, 12, 0.35) { GD.setFill(); tilePath.fill() } }
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(starting: G2, ending: G1)!.draw(in: bg, angle: -90)
    // Mähstreifen wie auf dem Fairway
    if detail {
        NSColor.white.withAlphaComponent(0.045).setFill()
        for i in stride(from: -4, to: 8, by: 2) {
            let p = NSBezierPath()
            let x = CGFloat(i) * 120 + bg.minX, h = bg.height
            p.move(to: NSPoint(x: x, y: bg.minY)); p.line(to: NSPoint(x: x + 120, y: bg.minY))
            p.line(to: NSPoint(x: x + 120 + h, y: bg.maxY)); p.line(to: NSPoint(x: x + h, y: bg.maxY)); p.close(); p.fill()
        }
    }
    // Lichtkante oben
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: bg.minX, y: bg.maxY - 224, width: bg.width, height: 224), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    if !fullBleed {
        NSColor.white.withAlphaComponent(0.12).setStroke()
        let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183); rim.lineWidth = 6; rim.stroke()
    }

    // Scorekarte, leicht gedreht
    let card = NSRect(x: 262, y: 232, width: 470, height: 580)
    rotated(-7, around: NSPoint(x: card.midX, y: card.midY)) {
        let cardPath = NSBezierPath(roundedRect: card, xRadius: 34, yRadius: 34)
        shadow(30, 18, 0.4) { CREAM.setFill(); cardPath.fill() }
        NSGraphicsContext.saveGraphicsState(); cardPath.addClip()
        // Kopfleiste mit Lochnummern
        let head = NSRect(x: card.minX, y: card.maxY - 92, width: card.width, height: 92)
        GD.setFill(); head.fill()
        GOLD.setFill(); NSRect(x: card.minX, y: head.minY - 10, width: card.width, height: 10).fill()
        if detail {
            for (i, n) in ["1", "2", "3", "4", "5"].enumerated() {
                text(n, font(40, .bold), CREAM.withAlphaComponent(0.92), center: NSPoint(x: card.minX + 62 + CGFloat(i) * 87, y: head.midY))
            }
            // Raster
            LINE.setStroke()
            for k in 1..<5 {
                let x = card.minX + CGFloat(k) * 94
                let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: card.minY)); p.line(to: NSPoint(x: x, y: head.minY - 10)); p.lineWidth = 3; p.stroke()
            }
            for k in 1..<6 {
                let y = card.minY + CGFloat(k) * 80
                let p = NSBezierPath(); p.move(to: NSPoint(x: card.minX, y: y)); p.line(to: NSPoint(x: card.maxX, y: y)); p.lineWidth = 3; p.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // Das Bogey-Kästchen mit der „5“
        let box = NSRect(x: card.midX - 150, y: card.minY + 120, width: 300, height: 300)
        CREAM.setFill(); box.insetBy(dx: -14, dy: -14).fill()
        let boxPath = NSBezierPath(rect: box.insetBy(dx: 17, dy: 17)); boxPath.lineWidth = 34; GD.setStroke(); boxPath.stroke()
        text("5", font(250, .black), GD, center: NSPoint(x: box.midX, y: box.midY - 4))
        if detail { text("+1", font(64, .heavy), GOLD, center: NSPoint(x: box.maxX + 30, y: box.maxY + 18)) }
    }

    // Bleistift diagonal über der Karte
    rotated(48, around: NSPoint(x: 700, y: 360)) {
        let len: CGFloat = 520, w: CGFloat = 58, x0: CGFloat = 700 - len / 2, y0: CGFloat = 360 - w / 2
        shadow(16, 12, 0.35) {
            let body = NSBezierPath(rect: NSRect(x: x0 + 90, y: y0, width: len - 90 - 80, height: w)); GOLD.setFill(); body.fill()
        }
        GOLDL.setFill(); NSRect(x: x0 + 90, y: y0 + w * 0.36, width: len - 170, height: w * 0.28).fill()
        GOLDD.setFill(); NSRect(x: x0 + 90, y: y0 + w * 0.34, width: len - 170, height: 3).fill(); NSRect(x: x0 + 90, y: y0 + w * 0.64, width: len - 170, height: 3).fill()
        STEEL.setFill(); NSRect(x: x0 + len - 80, y: y0, width: 36, height: w).fill()
        ROSE.setFill(); NSBezierPath(roundedRect: NSRect(x: x0 + len - 50, y: y0, width: 50, height: w), xRadius: 16, yRadius: 16).fill()
        let tip = NSBezierPath(); tip.move(to: NSPoint(x: x0 + 90, y: y0)); tip.line(to: NSPoint(x: x0, y: y0 + w / 2)); tip.line(to: NSPoint(x: x0 + 90, y: y0 + w)); tip.close()
        WOOD.setFill(); tip.fill()
        let lead = NSBezierPath(); lead.move(to: NSPoint(x: x0 + 28, y: y0 + w / 2 - 10)); lead.line(to: NSPoint(x: x0, y: y0 + w / 2)); lead.line(to: NSPoint(x: x0 + 28, y: y0 + w / 2 + 10)); lead.close()
        INK.setFill(); lead.fill()
    }

    // Golfball unten links
    let ball = NSRect(x: 196, y: 186, width: 190, height: 190)
    shadow(22, 14, 0.4) { NSColor.white.setFill(); NSBezierPath(ovalIn: ball).fill() }
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: ball).addClip()
    NSGradient(colors: [NSColor.white, NSColor(white: 0.93, alpha: 1), NSColor(white: 0.78, alpha: 1)])!
        .draw(in: NSBezierPath(ovalIn: ball), relativeCenterPosition: NSPoint(x: -0.35, y: 0.4))
    if detail {
        NSColor(white: 0.72, alpha: 0.55).setFill()
        for row in 0..<7 {
            for col in 0..<7 {
                let cx = ball.minX + 20 + CGFloat(col) * 26 + (row % 2 == 0 ? 0 : 13)
                let cy = ball.minY + 18 + CGFloat(row) * 26
                let dx = cx - ball.midX, dy = cy - ball.midY
                guard dx * dx + dy * dy < 88 * 88 else { continue }
                let r: CGFloat = 6.5 * (1 - (dx * dx + dy * dy) / (95 * 95) * 0.5)
                NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ px: Int, fullBleed: Bool = false) -> Data {
    // Randlose Icons ohne Transparenz (verlangt der App Store, sieht auf Home-Bildschirmen sauber aus)
    let info = fullBleed ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawIcon(detail: px >= 64, fullBleed: fullBleed)
    NSGraphicsContext.restoreGraphicsState()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

/// Logo für App-Kopf und PDFs: das randlose Motiv als abgerundete Kachel mit transparenten Ecken.
func renderLogo(_ px: Int) -> Data {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let r = CGFloat(px) * 0.225
    let rect = CGRect(x: 0, y: 0, width: px, height: px)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.clip()
    ctx.saveGState()
    ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawIcon(detail: true, fullBleed: true)
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
    // feine helle Kante, damit sich die Kachel auch auf grünem Grund (PDF-Kopf) abhebt
    let w = CGFloat(px) / 128
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor); ctx.setLineWidth(w * 2)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.strokePath()
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

// Mac
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    write(render(px), "mac/build/AppIcon.iconset/icon_\(name).png")
}
// iPhone
write(render(1024, fullBleed: true), "ios/GolfScorebuch/GolfScorebuch/Assets.xcassets/AppIcon.appiconset/icon.png")
// Web-App (Favicon, Home-Bildschirm, Manifest)
write(render(192, fullBleed: true), "server/icons/icon-192.png")
write(render(512, fullBleed: true), "server/icons/icon-512.png")
write(render(180, fullBleed: true), "server/icons/apple-touch-icon.png")
// Logo im App-Kopf und in den PDF-Ausdrucken
write(renderLogo(512), "web/bogey-club-logo.png")
print("Icons gezeichnet: Mac, iPhone, Web, Logo")
