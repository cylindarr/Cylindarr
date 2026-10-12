// swift-tools-version:6.2
import PackageDescription

// Everything the apps and their extensions share. The logic (pairing, the
// API client, what a share card does) is in CylindarrClientKit, which the
// tests run on the Mac with `swift test`; the SwiftUI views every target
// shows are in CylindarrClientUI.
let package = Package(
    name: "CylindarrClientKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CylindarrClientKit", targets: ["CylindarrClientKit"]),
        .library(name: "CylindarrClientUI", targets: ["CylindarrClientUI"]),
    ],
    dependencies: [
        // The server's own wire types.
        .package(path: "../../CylindarrAPI"),
    ],
    targets: [
        .target(name: "CylindarrClientKit", dependencies: [.product(name: "CylindarrAPI", package: "CylindarrAPI")]),
        .target(name: "CylindarrClientUI", dependencies: ["CylindarrClientKit"]),
        .testTarget(name: "CylindarrClientKitTests", dependencies: ["CylindarrClientKit"]),
    ]
)
