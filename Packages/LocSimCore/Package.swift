// swift-tools-version: 5.9
import PackageDescription

// Logic without UIKit, CoreLocation or the device library, so it also builds and
// runs its tests on Linux: swift test --package-path Packages/LocSimCore
let package = Package(
    name: "LocSimCore",
    platforms: [.iOS("17.4"), .macOS(.v14)],
    products: [.library(name: "LocSimCore", targets: ["LocSimCore"])],
    targets: [
        .target(name: "LocSimCore"),
        .testTarget(name: "LocSimCoreTests", dependencies: ["LocSimCore"]),
    ]
)
