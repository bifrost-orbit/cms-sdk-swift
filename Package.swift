// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CMSOrbit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "CMSOrbit", targets: ["CMSOrbit"]),
    ],
    targets: [
        .target(
            name: "CMSOrbit",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "CMSOrbitTests",
            dependencies: ["CMSOrbit"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]
        ),
    ]
)
