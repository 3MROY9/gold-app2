// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "GoldOrderBook",
    platforms: [.iOS("16.0")],
    products: [
        .iOSApplication(
            name: "GoldOrderBook",
            targets: ["AppModule"],
            bundleIdentifier: "com.goldorderbook.app",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: nil,
            accentColor: nil,
            supportedDeviceFamilies: [1, 2],
            supportedInterfaceOrientations: [
                .portrait,
                .portraitUpsideDown,
                .landscapeLeft,
                .landscapeRight
            ],
            capabilities: []
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "Sources/AppModule"
        )
    ]
)
