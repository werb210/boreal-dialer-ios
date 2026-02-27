// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BorealDialer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "BorealDialer", targets: ["BorealDialer"])
    ],
    dependencies: [
        // Add Swift Package dependencies here.
        // TwilioVoice SDK will be added via Xcode later.
    ],
    targets: [
        .executableTarget(
            name: "BorealDialer",
            dependencies: [],
            path: ".",
            sources: [
                "Sources/BorealDialer",
                "Core",
                "UI"
            ]
        ),
        .testTarget(
            name: "BorealDialerTests",
            dependencies: ["BorealDialer"],
            path: "Tests"
        )
    ]
)
