// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScreeningShared",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "ScreeningShared",
            targets: ["ScreeningShared"]
        )
    ],
    targets: [
        .target(
            name: "ScreeningShared"
        )
    ]
)
