// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EasyAsk",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "EasyAsk", targets: ["EasyAsk"])],
    targets: [.executableTarget(name: "EasyAsk", path: "Sources/EasyAsk")]
)
