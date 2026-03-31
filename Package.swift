// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "BorealDialer",
  platforms: [.iOS(.v15)],
  dependencies: [
    .package(url: "https://github.com/twilio/twilio-voice-ios", from: "6.6.0"),
  ],
  targets: [
    .target(
      name: "BorealDialer",
      dependencies: [
        .product(name: "TwilioVoice", package: "twilio-voice-ios"),
      ]
    )
  ]
)
