// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Capote",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "CapoteRemoteCore", targets: ["CapoteRemoteCore"]),
        .executable(name: "Capote", targets: ["Capote"]),
        .executable(name: "CapoteSession", targets: ["CapoteSessionHelper"]),
        .executable(name: "CapoteRemoteDaemon", targets: ["CapoteRemoteDaemon"])
    ],
    targets: [
        .target(
            name: "CapoteRemoteCore",
            path: "Sources/CapoteRemoteCore",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "Capote",
            dependencies: ["CapoteRemoteCore"],
            path: "Sources/Capote",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "CapoteSessionHelper",
            path: "Sources/CapoteSessionHelper",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "CapoteRemoteDaemon",
            dependencies: ["CapoteRemoteCore"],
            path: "Sources/CapoteRemoteDaemon",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "CapoteTests",
            dependencies: ["Capote", "CapoteRemoteCore"],
            path: "Tests/CapoteTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
