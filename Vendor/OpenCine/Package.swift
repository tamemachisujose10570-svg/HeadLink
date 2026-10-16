// swift-tools-version: 6.0
// HeadLink modification: distribution subset; original Swift source files are unchanged.
import PackageDescription
let package = Package(name: "OpenCine", platforms: [.iOS(.v17), .macOS(.v13)], products: [
.library(name: "OpenCineCore", targets: ["OpenCineCore"]),
.library(name: "OpenCineMedia", targets: ["OpenCineMedia"]),
.library(name: "OpenCineMotion", targets: ["OpenCineMotion"]),
.library(name: "OpenCineCameraVocabulary", targets: ["OpenCineCameraVocabulary"]),
.library(name: "OpenCineDJI", targets: ["OpenCineDJI"]),
.library(name: "OpenCineDJIApple", targets: ["OpenCineDJIApple"]),
.library(name: "OpenCineApple", targets: ["OpenCineApple"])
], targets: [
.target(name: "OpenCineCore", dependencies: []),
.target(name: "OpenCineMedia", dependencies: ["OpenCineCore"]),
.target(name: "OpenCineMotion", dependencies: ["OpenCineCore"]),
.target(name: "OpenCineCameraVocabulary", dependencies: ["OpenCineCore", "OpenCineMedia", "OpenCineMotion"]),
.target(name: "OpenCineDJI", dependencies: ["OpenCineCore", "OpenCineMedia", "OpenCineMotion", "OpenCineCameraVocabulary"]),
.target(name: "OpenCineDJIApple", dependencies: ["OpenCineCore", "OpenCineDJI", "OpenCineMedia", "OpenCineMotion"]),
.target(name: "OpenCineApple", dependencies: ["OpenCineCore", "OpenCineMedia"])
])
