import AppKit

// Bogey Club für den Mac: die Bogey-Club-Oberfläche in einem eigenen Fenster,
// Daten und Bilder liegen auf dem Mac, Scorekarten liest die Texterkennung von macOS.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { app.run() }
}
