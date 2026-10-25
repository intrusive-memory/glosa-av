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
  dependencies: [
    // Off Apple platforms only: SHA256 for Shot.digest. Apple builds use CryptoKit.
    .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
  ],
  targets: [
    // MARK: - GlosaCore (Foundation and CryptoKit)
    .target(
      name: "GlosaCore",
      dependencies: [
        .product(
          name: "Crypto",
          package: "swift-crypto",
          condition: .when(platforms: [.linux, .windows, .android])
        )
      ],
      resources: [.copy("schemas")],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),

    // MARK: - Tests
    .testTarget(
      name: "GlosaCoreTests",
      dependencies: ["GlosaCore"],
      resources: [.copy("Fixtures")],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
