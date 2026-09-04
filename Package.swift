// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sieve",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sieve",
            path: "Sources/Sieve",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
