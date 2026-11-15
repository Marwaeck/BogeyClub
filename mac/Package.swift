// swift-tools-version: 5.9
// Bogey Club für den Mac. Bauen: ./mac/build.sh (erzeugt mac/build/Bogey Club.app)
import PackageDescription

let package = Package(
    name: "BogeyClub",
    defaultLocalization: "de",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "BogeyClub", targets: ["BogeyClub"])
    ],
    dependencies: [
        // Scorekarten-Erkennung mit Apple Vision – dieselbe wie in der iPhone-App
        .package(path: "../BogeyScan")
    ],
    targets: [
        // Datenablage ohne Oberfläche (testbar)
        .target(name: "BogeyCore"),
        // Mac-App: Fenster, Menüs, Web-Oberfläche und Brücke zu Datenablage und Erkennung
        .executableTarget(name: "BogeyClub", dependencies: ["BogeyCore", .product(name: "BogeyScan", package: "BogeyScan")]),
        .testTarget(name: "BogeyCoreTests", dependencies: ["BogeyCore"])
    ]
)
