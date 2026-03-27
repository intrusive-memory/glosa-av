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
        .package(url: "https://github.com/intrusive-memory/SwiftCompartido.git", branch: "main"),
        .package(url: "https://github.com/intrusive-memory/SwiftBruja.git", branch: "main"),
        .package(url: "https://github.com/intrusive-memory/SwiftAcervo.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
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
    ]
)
