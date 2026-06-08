// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SleepChartKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8),
        .tvOS(.v15)
    ],
    products: [
        .library(
            name: "SleepChartKit",
            targets: ["SleepChartKit"]),
        .library(
            name: "SleepBankCore",
            targets: ["SleepBankCore"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "SleepChartKit"),
        .testTarget(
            name: "SleepChartKitTests",
            dependencies: ["SleepChartKit"]),
        // Sensor-agnostic nap domain: onset detection, state machine, alarm timing.
        // Pure Foundation so it is unit-testable without devices and reusable on
        // both the phone and the watch.
        .target(
            name: "SleepBankCore"),
        .testTarget(
            name: "SleepBankCoreTests",
            dependencies: ["SleepBankCore"]),
    ]
)
