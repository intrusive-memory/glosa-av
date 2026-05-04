// swift-tools-version: 6.2

import Foundation
import PackageDescription

// In CI we always pin to released remotes. Locally, prefer a sibling checkout
// at ../<name> if present so in-flight changes can be exercised end-to-end
// without publishing a release. Falls back to the remote pin if the sibling
// directory is missing, so fresh clones still build.
let useLocalSiblings = ProcessInfo.processInfo.environment["CI"] != "true"

func sibling(_ name: String, remote: String, from version: Version) -> Package.Dependency {
  let localPath = "../\(name)"
  if useLocalSiblings && FileManager.default.fileExists(atPath: localPath) {
    return .package(path: localPath)
  }
  return .package(url: remote, .upToNextMajor(from: version))
}

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
        sibling("SwiftCompartido", remote: "https://github.com/intrusive-memory/SwiftCompartido.git", from: "7.0.2"),
        sibling("SwiftBruja", remote: "https://github.com/intrusive-memory/SwiftBruja.git", from: "1.6.1"),
        sibling("SwiftAcervo", remote: "https://github.com/intrusive-memory/SwiftAcervo.git", from: "0.11.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/jkandzi/Progress.swift", from: "0.4.0"),
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
