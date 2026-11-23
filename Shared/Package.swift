// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DesktopARShared",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "DesktopARShared", targets: ["DesktopARShared"])],
    targets: [
        .target(name: "DesktopARShared"),
        .testTarget(name: "DesktopARSharedTests", dependencies: ["DesktopARShared"]),
    ]
)
