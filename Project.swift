import ProjectDescription
import Foundation

let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"

let project = Project(
    name: "GemmaEdgeGallery",
    packages: [
        // NOTE: v0.12.0 release tag has packaging issues (missing macOS xcframework slice,
        // unsafe build flags). main HEAD (aeefa9b) is also currently broken.
        // Pinning to last known-good commit. Re-evaluate when v0.13.0+ is released.
        .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .revision("3a97cbfe4e788916ede49feb9526a3854a3b3946"))
    ],
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": .string(teamId),
            "CODE_SIGN_STYLE": "Automatic"
        ]
    ),
    targets: [
        .target(
            name: "GemmaEdgeGallery_iOS",
            destinations: .iOS,
            product: .app,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery",
            deploymentTargets: .iOS("26.5"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                // Enable iTunes/Finder file sharing so models can be copied to Documents/
                "UIFileSharingEnabled": true,
                // Allow the Files app to browse and manage model files in Documents/
                "LSSupportsOpeningDocumentsInPlace": true,
                // Support opening .litertlm files directly from other apps
                "UISupportsDocumentBrowser": true,
            ]),
            sources: ["Sources/**"],
            // Increased Memory Limit entitlement for large model inference.
            // NOTE: extended-virtual-addressing requires paid Apple Developer Program;
            // increased-memory-limit works with personal teams (matches zealous-bose config).
            entitlements: .file(path: "GemmaEdgeGallery_iOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM")
            ]
        ),
        .target(
            name: "GemmaEdgeGallery_iOSTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.Tests",
            deploymentTargets: .iOS("26.5"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "GemmaEdgeGallery_iOS")
            ]
        ),
        .target(
            name: "GemmaEdgeGallery_macOS",
            destinations: .macOS,
            product: .app,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["Sources/**"],
            dependencies: [
                .package(product: "LiteRTLM")
            ]
        ),
        .target(
            name: "GemmaEdgeGallery_macOSTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac.Tests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [
                .target(name: "GemmaEdgeGallery_macOS")
            ]
        )
    ],
    schemes: [
        .scheme(
            name: "GemmaEdgeGallery_iOS",
            shared: true,
            buildAction: .buildAction(targets: ["GemmaEdgeGallery_iOS"]),
            testAction: .targets(
                ["GemmaEdgeGallery_iOSTests"],
                configuration: .debug,
                options: .options(coverage: true)
            ),
            runAction: .runAction(configuration: .debug)
        ),
        .scheme(
            name: "GemmaEdgeGallery_macOS",
            shared: true,
            buildAction: .buildAction(targets: ["GemmaEdgeGallery_macOS"]),
            testAction: .targets(
                ["GemmaEdgeGallery_macOSTests"],
                configuration: .debug,
                options: .options(coverage: true)
            ),
            runAction: .runAction(configuration: .debug)
        )
    ]
)

