// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VlogClawStudio",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "VlogClawStudio",
            path: "Sources/VlogClawStudio",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
            ]
        ),
    ]
)
