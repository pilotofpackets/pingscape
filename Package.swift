// swift-tools-version: 6.0
import PackageDescription

// Pingscape as a library, for apps that embed it (see App/Support/Embedding.swift).
// The app itself is built from project.yml and does not use this file.
//
// NetKit is a target here rather than a dependency on Packages/NetKit: SwiftPM
// rejects a local path dependency in a package that is fetched by branch or version.
let package = Package(
    name: "Pingscape",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "PingscapeUI", targets: ["PingscapeUI"]),
    ],
    targets: [
        .target(name: "NetKit", path: "Packages/NetKit/Sources/NetKit"),
        .target(
            name: "PingscapeUI",
            dependencies: ["NetKit"],
            path: "App",
            exclude: [
                "Info.plist",
                "Intents",
                "Pingscape.entitlements",
                "PingscapeApp.swift",
                "Resources/AppIcon.icon",
                "Resources/AppShortcuts.xcstrings",
                "Resources/InfoPlist.xcstrings",
                "Resources/Localizable.xcstrings",
                "Resources/PrivacyInfo.xcprivacy",
                "Support/SelfTest.swift",
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/oui.txt"),
            ]
        ),
    ]
)
