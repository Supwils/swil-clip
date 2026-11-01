// swift-tools-version: 6.0
import PackageDescription

// SwilClip v2 — deliberately dependency-free. See
// docs/design-v2.md §4.2.
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
        .library(name: "SwilClipUI", targets: ["SwilClipUI"]),
    ],
    targets: [
        .target(
            name: "SwilClipCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The shell as a library, so a test target can reach it. SPM cannot
        // reliably `@testable import` an executable, which is why the larger
        // half of this codebase had no tests and shipped four wiring bugs.
        .target(
            name: "SwilClipUI",
            dependencies: ["SwilClipCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // main.swift only.
        .executableTarget(
            name: "SwilClip",
            dependencies: ["SwilClipUI"],
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
        .testTarget(
            name: "SwilClipUITests",
            dependencies: ["SwilClipUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
