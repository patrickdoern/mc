// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let vendored = FileManager.default.fileExists(atPath: packageRoot + "/vendor/lib/libssh2.a")
let includePath = vendored ? packageRoot + "/vendor/include" : "/opt/homebrew/include"
let libraryPath = vendored ? packageRoot + "/vendor/lib" : "/opt/homebrew/lib"
let sshLibraries: [LinkerSetting] = vendored
    ? [.linkedLibrary("ssh2"), .linkedLibrary("ssl"), .linkedLibrary("crypto"), .linkedLibrary("z")]
    : [.linkedLibrary("ssh2")]
let headerSearch: [SwiftSetting] = [.unsafeFlags(["-Xcc", "-I" + includePath])]

let package = Package(
    name: "MC",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CLibSSH2"),
        .target(
            name: "MCCore",
            dependencies: ["CLibSSH2"],
            swiftSettings: headerSearch,
            linkerSettings: [.unsafeFlags(["-L" + libraryPath])] + sshLibraries
        ),
        .executableTarget(name: "MC", dependencies: ["MCCore"], resources: [.copy("Resources/AppIcon.icns")], swiftSettings: headerSearch),
        .testTarget(name: "MCCoreTests", dependencies: ["MCCore"], swiftSettings: headerSearch),
    ],
    swiftLanguageModes: [.v5]
)
