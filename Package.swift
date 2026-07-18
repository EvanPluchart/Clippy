// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clippy",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Clippy", targets: ["Clippy"])],
    targets: [
        .executableTarget(name: "Clippy", path: "Clippy", exclude: ["Resources/Info.plist", "Resources/Clippy.entitlements", "Resources/ClippyDebug.entitlements", "Resources/PrivacyInfo.xcprivacy", "Resources/Assets.xcassets", "Resources/Localizable.xcstrings"]),
        .testTarget(name: "ClippyTests", dependencies: ["Clippy"], path: "ClippyTests")
    ],
    swiftLanguageModes: [.v6]
)
