// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SonoBarKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SonoBarKit", targets: ["SonoBarKit"]),
    ],
    targets: [
        .target(name: "SonoBarKit"),
        .testTarget(name: "SonoBarKitTests", dependencies: ["SonoBarKit"]),
    ]
)
