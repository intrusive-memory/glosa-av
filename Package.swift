// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "glosa-av",
  platforms: [
    .macOS(.v26),
    .iOS(.v26),
  ],
  products: [
    .library(name: "GlosaCore", targets: ["GlosaCore"])
  ],
  dependencies: [],
  targets: [
    // MARK: - GlosaCore (Foundation-only)
    .target(
      name: "GlosaCore",
      dependencies: [],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),

    // MARK: - Tests
    .testTarget(
      name: "GlosaCoreTests",
      dependencies: ["GlosaCore"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
