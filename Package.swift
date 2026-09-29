// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nudge", targets: ["Nudge"])
    ],
    targets: [
        .executableTarget(
            name: "Nudge",
            path: "Sources/Nudge",
            resources: []
        )
    ]
)
