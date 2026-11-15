// swift-tools-version: 5.9
// Scorekarten-Erkennung für iPhone- und Mac-App: Apple Vision (Texterkennung auf dem Gerät, offline)
// plus die Auswertung zu Par, Lochvorgaben und Spielerzeilen. Wird von ios/ und mac/ eingebunden.
import PackageDescription

let package = Package(
    name: "BogeyScan",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "BogeyScan", targets: ["BogeyScan"])
    ],
    targets: [
        .target(name: "BogeyScan"),
        .testTarget(name: "BogeyScanTests", dependencies: ["BogeyScan"])
    ]
)
