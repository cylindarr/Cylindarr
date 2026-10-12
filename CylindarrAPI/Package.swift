// swift-tools-version:6.0
import PackageDescription

// The JSON API's wire types, on their own so the Apple apps can use them
// without resolving the server's dependencies. Foundation only.
let package = Package(
    name: "CylindarrAPI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CylindarrAPI", targets: ["CylindarrAPI"])],
    targets: [
        .target(name: "CylindarrAPI"),
        .testTarget(name: "CylindarrAPITests", dependencies: ["CylindarrAPI"]),
    ]
)
