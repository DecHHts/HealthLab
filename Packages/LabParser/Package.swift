// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LabParser",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LabParser", targets: ["LabParser"]),
    ],
    targets: [
        .target(name: "LabParser"),
        .testTarget(name: "LabParserTests", dependencies: ["LabParser"], resources: [.copy("Fixtures")]),
    ]
)
