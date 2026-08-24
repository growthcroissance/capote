// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Capote",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Capote", targets: ["Capote"]),
        .executable(name: "CapoteSession", targets: ["CapoteSessionHelper"])
    ],
    targets: [
        .executableTarget(
            name: "Capote",
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
        .testTarget(
            name: "CapoteTests",
            dependencies: ["Capote"],
            path: "Tests/CapoteTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
