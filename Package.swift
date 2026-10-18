// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BeHereNow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BeHereNow", targets: ["BeHereNow"])],
    targets: [
        .executableTarget(name: "BeHereNow"),
        .testTarget(name: "BeHereNowTests", dependencies: ["BeHereNow"]),
    ]
)
