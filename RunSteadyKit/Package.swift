// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunSteadyKit",
    platforms: [.iOS(.v18), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "RunSteadyKit", targets: ["RunSteadyKit"])
    ],
    targets: [
        .target(name: "RunSteadyKit"),
        .testTarget(name: "RunSteadyKitTests", dependencies: ["RunSteadyKit"]),
    ]
)
