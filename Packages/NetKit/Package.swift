// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NetKit", targets: ["NetKit"]),
    ],
    targets: [
        .target(name: "NetKit"),
        .testTarget(name: "NetKitTests", dependencies: ["NetKit"]),
    ]
)
