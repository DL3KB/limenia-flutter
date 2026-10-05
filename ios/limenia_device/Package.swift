// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "limenia_device",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "limenia-device", targets: ["limenia_device"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "limenia_device",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                // DeviceCheck is no required reason API and the plugin collects no data itself: the
                // privacy manifest is empty.
                .process("PrivacyInfo.xcprivacy")
            ],
            linkerSettings: [
                .linkedFramework("DeviceCheck")
            ]
        )
    ]
)
