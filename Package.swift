// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kost",
    platforms: [.macOS(.v14)],
    targets: [
        // Rechnen, Speichern, ChatGPT und Produktsuche – ohne Oberfläche, damit es prüfbar bleibt.
        .target(name: "KostKern"),
        .executableTarget(name: "Kost", dependencies: ["KostKern"]),
        .testTarget(name: "KostKernTests", dependencies: ["KostKern"]),
    ]
)
