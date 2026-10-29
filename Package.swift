// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ThreeFBrowser",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ThreeFBrowser", targets: ["ThreeFBrowser"])
    ],
    targets: [
        .executableTarget(name: "ThreeFBrowser")
    ]
)
