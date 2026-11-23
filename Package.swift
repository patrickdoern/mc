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
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.5.1"),
    ],
    targets: [
        .systemLibrary(name: "CLibSSH2"),
        .systemLibrary(name: "CCurl"),
        .target(
            name: "MCCore",
            dependencies: ["CLibSSH2", "CCurl"],
            swiftSettings: headerSearch,
            linkerSettings: [.unsafeFlags(["-L" + libraryPath]), .linkedFramework("NetFS")] + sshLibraries
        ),
        .executableTarget(name: "MC", dependencies: ["MCCore", .product(name: "SwiftTerm", package: "SwiftTerm")], exclude: ["Resources/en.lproj"], resources: [.copy("Resources/AppIcon.icns")], swiftSettings: headerSearch),
        .testTarget(name: "MCCoreTests", dependencies: ["MCCore"], swiftSettings: headerSearch),
    ],
    swiftLanguageModes: [.v5]
)
