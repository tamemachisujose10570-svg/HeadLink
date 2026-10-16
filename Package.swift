// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "HeadLink", platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "HeadLinkCore", targets: ["HeadLinkCore"])],
    dependencies: [.package(path: "Vendor/OpenCine")],
    targets: [
        .target(name: "HeadLinkCore"),
        .testTarget(name: "HeadLinkCoreTests", dependencies: ["HeadLinkCore",
            .product(name: "OpenCineDJI", package: "OpenCine")])
    ])
