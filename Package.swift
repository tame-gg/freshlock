// swift-tools-version: 6.0
//
//  Package.swift
//  FreshLock
//
//  The package is intentionally split into two targets:
//
//  • `FreshLockCore` — a platform-agnostic-ish library that holds the models,
//    services and business logic. It contains no `@main` entry point, which
//    keeps it fully unit-testable with `swift test` (and importable by the
//    background helper without dragging in the UI layer).
//
//  • `FreshLock` — the executable app target. It owns the SwiftUI/AppKit entry
//    point, the menu-bar scene, the overlay windows and all the views. It
//    depends on `FreshLockCore` for everything that isn't presentation.
//
//  This separation is what makes the "GUI only manages configuration, the
//  helper does the protecting" requirement expressible in code: both the app
//  and (future) helper link `FreshLockCore`.
//
import PackageDescription

let package = Package(
    name: "FreshLock",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "FreshLockCore", targets: ["FreshLockCore"]),
        .library(name: "FreshLockEngine", targets: ["FreshLockEngine"]),
        .executable(name: "FreshLock", targets: ["FreshLock"]),
        .executable(name: "FreshLockHelper", targets: ["FreshLockHelper"])
    ],
    targets: [
        .target(
            name: "FreshLockCore",
            path: "Sources/FreshLockCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The AppKit-based locking engine, shared by the GUI and the helper so
        // "the helper does the protecting" is a real, buildable arrangement.
        .target(
            name: "FreshLockEngine",
            dependencies: ["FreshLockCore"],
            path: "Sources/FreshLockEngine",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "FreshLock",
            dependencies: ["FreshLockCore", "FreshLockEngine"],
            path: "Sources/FreshLock",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The background helper: a headless accessory process that runs the
        // engine independently of the settings UI.
        .executableTarget(
            name: "FreshLockHelper",
            dependencies: ["FreshLockCore", "FreshLockEngine"],
            path: "Sources/FreshLockHelper",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FreshLockCoreTests",
            dependencies: ["FreshLockCore"],
            path: "Tests/FreshLockCoreTests"
        )
    ]
)
