// swift-tools-version: 6.0
// UIに依存しない中核 (モデル・通信・送信内容の組み立て・ViewModel・通知判断・傾向計算)。
// Foundation と Observation だけに依存するので、macOS/Linux の `swift test` でも検証できる。
import PackageDescription

let package = Package(
    name: "TaikenCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TaikenCore", targets: ["TaikenCore"]),
    ],
    targets: [
        .target(name: "TaikenCore"),
        .testTarget(name: "TaikenCoreTests", dependencies: ["TaikenCore"]),
    ],
    swiftLanguageModes: [.v6]
)
