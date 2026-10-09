// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BlockingCore",
    platforms: [.iOS("17.4"), .macOS(.v13)],
    products: [.library(name: "BlockingCore", targets: ["BlockingCore"])],
    targets: [
        .target(name: "BlockingCore"),
        .testTarget(name: "BlockingCoreTests", dependencies: ["BlockingCore"])
    ]
)
