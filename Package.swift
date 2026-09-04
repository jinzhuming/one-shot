// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shot",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Shot", targets: ["Shot"])
    ],
    targets: [
        .target(
            name: "ShotKit",
            path: "Sources/ShotKit",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Shot",
            dependencies: ["ShotKit"],
            path: "Sources/Shot",
            resources: [
                .process("Localizable.xcstrings"),
                .process("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ShotKitTests",
            dependencies: ["ShotKit"],
            path: "Tests/ShotKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "ShotTests",
            dependencies: ["Shot"],
            path: "Tests/ShotTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
