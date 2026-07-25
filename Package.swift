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
        .executable(name: "AppLock", targets: ["AppLock"])
    ],
    targets: [
        .target(
            name: "AppLockCore",
            path: "Sources/AppLockCore",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "AppLock",
            dependencies: ["AppLockCore"],
            path: "Sources/AppLock",
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
