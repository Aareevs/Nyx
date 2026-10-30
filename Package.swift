// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "Nyx",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "HIDEventSystem",
            path: "Sources/HIDEventSystem"
        ),
        .systemLibrary(
            name: "VMStatisticsCompat",
            path: "Sources/VMStatisticsCompat"
        ),
        .executableTarget(
            name: "Nyx",
            dependencies: ["VMStatisticsCompat", "HIDEventSystem"],
            path: "Sources/Nyx"
        )
    ]
)
