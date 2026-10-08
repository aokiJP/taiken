// swift-tools-version: 6.0
// UIに依存しない中核 (モデル・通信・送信内容の組み立て・ViewModel・通知判断・傾向計算・体験ライブラリ・技の樹)。
// Foundation と Observation だけに依存するので、macOS/Linux の `swift test` でも検証できる。
import PackageDescription

let package = Package(
    name: "TaikenCore",
    defaultLocalization: "ja",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "TaikenCore", targets: ["TaikenCore"]),
    ],
    targets: [
        .target(
            name: "TaikenCore",
            // 体験ライブラリと10の要素 (contracts/content.ja.json) と、技の樹 (contracts/skills.ja.json) のコピー。
            // テストで一致を確認する
            resources: [.copy("Resources/content.ja.json"), .copy("Resources/skills.ja.json")]
        ),
        .testTarget(name: "TaikenCoreTests", dependencies: ["TaikenCore"]),
    ],
    swiftLanguageModes: [.v6]
)
