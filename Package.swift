// swift-tools-version: 6.0
import PackageDescription

let homebrewInclude: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I/opt/homebrew/include"])]

let package = Package(
    name: "MC",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CLibSSH2"),
        .target(
            name: "MCCore",
            dependencies: ["CLibSSH2"],
            swiftSettings: homebrewInclude,
            linkerSettings: [.unsafeFlags(["-L/opt/homebrew/lib"]), .linkedLibrary("ssh2")]
        ),
        .executableTarget(name: "MC", dependencies: ["MCCore"], resources: [.copy("Resources/AppIcon.icns")], swiftSettings: homebrewInclude),
        .testTarget(name: "MCCoreTests", dependencies: ["MCCore"], swiftSettings: homebrewInclude),
    ],
    swiftLanguageModes: [.v5]
)
