// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "VoicePrompt",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "VoicePrompt", targets: ["VoicePrompt"])],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.1")
    ],
    targets: [
        .target(name: "VoicePromptCore"),
        .executableTarget(name: "VoicePrompt", dependencies: [
            "VoicePromptCore",
            .product(name: "WhisperKit", package: "argmax-oss-swift")
        ]),
        .executableTarget(name: "VoicePromptChecks", dependencies: ["VoicePromptCore"])
    ]
)
