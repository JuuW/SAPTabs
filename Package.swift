// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SAPTabs",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SAPTabs",
            path: "Sources/SAPTabs"
        )
    ]
)
