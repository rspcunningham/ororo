// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OroroKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "OroroKit", targets: ["OroroKit"]),
    ],
    targets: [
        .target(name: "OroroKit"),
        .testTarget(
            name: "OroroKitTests",
            dependencies: ["OroroKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
