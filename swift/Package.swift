// swift-tools-version: 6.0
import PackageDescription

// SwilClip v2 — deliberately dependency-free. See
// docs/superpowers/specs/2026-08-20-swift-rewrite-prompt-library-design.md §4.2.
//
// SwilClipCore links no AppKit, so the entire test suite runs headless. The app
// target holds only what genuinely needs a window server.
let package = Package(
    name: "SwilClip",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SwilClip", targets: ["SwilClip"]),
        .executable(name: "swilclip-recover", targets: ["SwilClipRecover"]),
        .library(name: "SwilClipCore", targets: ["SwilClipCore"]),
    ],
    targets: [
        .target(
            name: "SwilClipCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "SwilClip",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Rescue utility. The v1 history file is never written or deleted, which
        // makes it a permanent fallback — but only if something can read it back.
        .executableTarget(
            name: "SwilClipRecover",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SwilClipCoreTests",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
