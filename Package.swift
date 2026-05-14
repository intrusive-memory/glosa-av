// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "glosa-av",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "GlosaCore", targets: ["GlosaCore"]),
        .library(name: "GlosaAnnotation", targets: ["GlosaAnnotation"]),
        .library(name: "GlosaDirector", targets: ["GlosaDirector"]),
        .executable(name: "glosa", targets: ["glosa"]),
    ],
    dependencies: [
        .package(url: "https://github.com/intrusive-memory/SwiftCompartido.git", .upToNextMajor(from: "7.0.5")),
        .package(url: "https://github.com/intrusive-memory/SwiftBruja.git", .upToNextMajor(from: "1.6.3")),
        .package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", .upToNextMajor(from: "0.13.0")),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.1"),
        .package(url: "https://github.com/jkandzi/Progress.swift", from: "0.4.0"),
        // Cap to 0.5.x: swift-tokenizers 0.6.0 switched its Rust binary target from
        // XCFramework to artifactbundle, breaking `canImport(TokenizersRust)` in
        // xcodebuild and producing "cannot find type 'RustBuffer' in scope" errors in
        // TokenizersFFI. Pulled in transitively via mlx-swift-lm; pin here directly
        // so SwiftPM resolves down. Re-evaluate when upstream restores xcodebuild
        // compatibility.
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", .upToNextMinor(from: "0.5.0")),
    ],
    targets: [
        // MARK: - GlosaCore (Foundation-only)
        .target(
            name: "GlosaCore",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - GlosaAnnotation (GlosaCore + SwiftCompartido)
        .target(
            name: "GlosaAnnotation",
            dependencies: [
                "GlosaCore",
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - GlosaDirector (GlosaAnnotation + SwiftBruja + SwiftAcervo)
        .target(
            name: "GlosaDirector",
            dependencies: [
                "GlosaAnnotation",
                .product(name: "SwiftBruja", package: "SwiftBruja"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - glosa CLI
        .executableTarget(
            name: "glosa",
            dependencies: [
                "GlosaDirector",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftAcervo", package: "SwiftAcervo"),
                .product(name: "Progress", package: "Progress.swift"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),

        // MARK: - Tests
        .testTarget(
            name: "GlosaCoreTests",
            dependencies: ["GlosaCore"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "GlosaAnnotationTests",
            dependencies: [
                "GlosaAnnotation",
                "GlosaCore",
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "GlosaDirectorTests",
            dependencies: [
                "GlosaDirector",
                "GlosaAnnotation",
                "GlosaCore",
                .product(name: "SwiftCompartido", package: "SwiftCompartido"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
