// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VocabLook",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .executableTarget(
            name: "VocabLook",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        )
    ]
)
