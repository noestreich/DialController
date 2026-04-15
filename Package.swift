// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DialController",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "DialController",
            path: "Sources/DialController",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
