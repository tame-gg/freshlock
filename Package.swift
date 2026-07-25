// swift-tools-version: 6.0
//
//  Package.swift
//  AppLock
//
//  The package is intentionally split into two targets:
//
//  • `AppLockCore` — a platform-agnostic-ish library that holds the models,
//    services and business logic. It contains no `@main` entry point, which
//    keeps it fully unit-testable with `swift test` (and importable by the
//    background helper without dragging in the UI layer).
//
//  • `AppLock` — the executable app target. It owns the SwiftUI/AppKit entry
//    point, the menu-bar scene, the overlay windows and all the views. It
//    depends on `AppLockCore` for everything that isn't presentation.
//
//  This separation is what makes the "GUI only manages configuration, the
//  helper does the protecting" requirement expressible in code: both the app
//  and (future) helper link `AppLockCore`.
//
import PackageDescription

let package = Package(
    name: "AppLock",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "AppLockCore", targets: ["AppLockCore"]),
        .library(name: "AppLockEngine", targets: ["AppLockEngine"]),
        .executable(name: "AppLock", targets: ["AppLock"]),
        .executable(name: "AppLockHelper", targets: ["AppLockHelper"])
    ],
    targets: [
        .target(
            name: "AppLockCore",
            path: "Sources/AppLockCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The AppKit-based locking engine, shared by the GUI and the helper so
        // "the helper does the protecting" is a real, buildable arrangement.
        .target(
            name: "AppLockEngine",
            dependencies: ["AppLockCore"],
            path: "Sources/AppLockEngine",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AppLock",
            dependencies: ["AppLockCore", "AppLockEngine"],
            path: "Sources/AppLock",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        // The background helper: a headless accessory process that runs the
        // engine independently of the settings UI.
        .executableTarget(
            name: "AppLockHelper",
            dependencies: ["AppLockCore", "AppLockEngine"],
            path: "Sources/AppLockHelper",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "AppLockCoreTests",
            dependencies: ["AppLockCore"],
            path: "Tests/AppLockCoreTests"
        )
    ]
)
