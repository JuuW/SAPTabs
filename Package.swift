// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SAPGUITabs",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SAPGUITabs",
            path: "Sources/SAPGUITabs"
        )
    ]
)
