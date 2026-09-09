// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sieve",
    // Only constrains Apple builds; Windows and Linux builds are unaffected by it.
    platforms: [.macOS(.v14)],
    products: [
        // The portable engine: database providers, deduplication, parsing and
        // exporters. No Apple frameworks, so it builds on Windows and Linux too.
        .library(name: "SieveCore", targets: ["SieveCore"])
    ],
    targets: [
        // Deliberately carries no `platforms:` pin and imports no Apple UI
        // framework. Anything added here must compile on Windows.
        .target(
            name: "SieveCore",
            path: "Sources/SieveCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Runs on every platform the core claims to support, so a Windows regression in
        // the engine's behaviour shows up as a red test rather than at a user's desk.
        .testTarget(
            name: "SieveCoreTests",
            dependencies: ["SieveCore"],
            path: "Tests/SieveCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Sieve",
            dependencies: ["SieveCore"],
            path: "Sources/Sieve",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
