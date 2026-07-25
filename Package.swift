// swift-tools-version: 6.0
//
//  Package.swift
//  FreshLock
//
//  The package is intentionally split into targets:
//
//  • `FreshLockCore` — models, services, unlock state (unit-testable).
//  • `FreshLockEngine` — AppKit lock pipeline (overlay + LA), shared by GUI/helper.
//  • `FreshLockEnforce` — pure exec-gate policy for Phase 1 (no ES link).
//  • `FreshLockEnforceExtension` — Endpoint Security AUTH_EXEC scaffolding.
//    Not embedded in the .app yet; requires Apple's managed ES entitlement.
//  • `FreshLock` / `FreshLockHelper` — GUI and background helper executables.
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
        .library(name: "FreshLockEnforce", targets: ["FreshLockEnforce"]),
        .executable(name: "FreshLock", targets: ["FreshLock"]),
        .executable(name: "FreshLockHelper", targets: ["FreshLockHelper"]),
        .executable(name: "FreshLockEnforceExtension", targets: ["FreshLockEnforceExtension"])
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
        // Pure policy for kernel-held AUTH_EXEC (Phase 1). No EndpointSecurity
        // link — keeps `swift test` free of entitlement/privilege requirements.
        .target(
            name: "FreshLockEnforce",
            path: "Sources/FreshLockEnforce",
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
        // ES AUTH_EXEC client scaffolding. Links EndpointSecurity; does not ship
        // inside FreshLock.app until packaging + Apple entitlement are ready.
        .executableTarget(
            name: "FreshLockEnforceExtension",
            dependencies: ["FreshLockEnforce"],
            path: "Sources/FreshLockEnforceExtension",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                .linkedFramework("EndpointSecurity")
            ]
        ),
        .testTarget(
            name: "FreshLockCoreTests",
            dependencies: ["FreshLockCore", "FreshLockEnforce"],
            path: "Tests/FreshLockCoreTests"
        )
    ]
)
