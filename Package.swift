// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cylindarr",
    platforms: [
        // macOS is declared so the whole logic suite runs with `swift test` on
        // the Mac: no container, no network, no yt-dlp. Everything that decides
        // anything lives in CylindarrKit, which is why that matters.
        .macOS(.v14)
    ],
    products: [
        .library(name: "CylindarrKit", targets: ["CylindarrKit"]),
        .executable(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.115.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.4.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0"),
        // The JSON API's types, shared with the Apple apps in Apple/.
        .package(path: "CylindarrAPI"),
    ],
    targets: [
        // All decisions live here. No Vapor, no network, no filesystem except
        // behind a protocol in Seams/. yt-dlp is never linked, only described:
        // the tests replay its real JSON and its real error text.
        .target(name: "CylindarrKit", path: "Sources/CylindarrKit"),
        // The real seams that are not HTTP: yt-dlp as a process, and the
        // filesystem. Kept out of CylindarrKit so the logic suite never
        // starts a process or touches a disk.
        .target(
            name: "CylindarrSystem",
            dependencies: [.target(name: "CylindarrKit")],
            path: "Sources/CylindarrSystem"
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                .target(name: "CylindarrKit"),
                .target(name: "CylindarrSystem"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CylindarrAPI", package: "CylindarrAPI"),
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "CylindarrKitTests",
            dependencies: [.target(name: "CylindarrKit")],
            path: "Tests/CylindarrKitTests",
            // Real feeds, yt-dlp output and error text, and invented library trees.
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "CylindarrSystemTests",
            dependencies: [.target(name: "CylindarrSystem"), .target(name: "CylindarrKit")],
            path: "Tests/CylindarrSystemTests"
        ),
    ]
)
