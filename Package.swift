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
        ),
        .package(
            url: "https://github.com/twilio/conversations-ios",
            from: "4.0.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "BorealDialer",
            dependencies: [
                .product(name: "TwilioVoice", package: "twilio-voice-ios"),
                .product(name: "TwilioConversationsClient", package: "conversations-ios")
            ],
            path: ".",
            sources: [
                "Sources/BorealDialer",
                "Core",
                "UI",
                "Features"
            ]
        ),
        .testTarget(
            name: "BorealDialerTests",
            dependencies: ["BorealDialer"],
            path: "Tests"
        )
    ]
)
