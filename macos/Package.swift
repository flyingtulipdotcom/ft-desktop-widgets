// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FlyingTulip",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FlyingTulip", targets: ["FlyingTulip"]),
    ],
    targets: [
        // Data, parsing, formatting, alerts, links and usage stats. No UI, so it is unit tested on its own.
        .target(name: "FTWidgetCore"),
        // The menu bar app.
        .executableTarget(name: "FlyingTulip", dependencies: ["FTWidgetCore"]),
        .testTarget(
            name: "FTWidgetCoreTests",
            dependencies: ["FTWidgetCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
