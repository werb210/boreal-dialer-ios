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
        .package(
            url: "https://github.com/twilio/twilio-voice-ios",
            from: "6.10.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "BorealDialer",
            dependencies: [
                .product(name: "TwilioVoice", package: "twilio-voice-ios")
            ],
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
