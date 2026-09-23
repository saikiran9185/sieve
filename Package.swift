// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sieve",
    // Only constrains Apple builds; Windows and Linux builds are unaffected by it.
    // iOS is here for SieveCore alone — the engine an iPad app would sit on. The Mac
    // executable below is AppKit through and through and does not build for it.
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        // The portable engine: database providers, deduplication, parsing and
        // exporters. No Apple frameworks, so it builds on Windows and Linux too.
        .library(name: "SieveCore", targets: ["SieveCore"])
    ],
    targets: [
        // Imports no Apple UI framework, so it builds for Windows, Linux, macOS and iOS
        // alike. Anything added here must hold to that. (SwiftPM has no per-target
        // platform setting — the package-level pin above applies here too on Apple
        // platforms, and is simply ignored elsewhere.)
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
