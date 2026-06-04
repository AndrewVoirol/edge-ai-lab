import ProjectDescription
import Foundation

let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"

let project = Project(
    name: "GemmaEdgeGallery",
    packages: [
        // LiteRT-LM v0.13.1 — patch release (June 3 2026) with bug fixes on v0.13.0.
        // Pinned by branch (not semver) because the SDK uses .unsafeFlags(["-Xlinker",
        // "-all_load"]) which SPM blocks for versioned dependencies but allows for
        // branch/revision pins. The release/v0.13 branch tracks the v0.13.1 tag.
        .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .branch("release/v0.13"))
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
        ),
        .target(
            name: "RawBenchmark",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.RawBenchmark",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["RawBenchmark/**"],
            dependencies: [
                .package(product: "LiteRTLM")
            ],
            settings: .settings(
                base: [
                    "LD_RUNPATH_SEARCH_PATHS": .array([
                        "@executable_path",
                        "@executable_path/../lib",
                        "$(BUILT_PRODUCTS_DIR)"
                    ]),
                    "HEADERPAD_MAX_INSTALL_NAMES": "YES"
                ]
            )
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
        ),
        .scheme(
            name: "RawBenchmark",
            shared: true,
            buildAction: .buildAction(targets: ["RawBenchmark"]),
            runAction: .runAction(configuration: .release)
        )
    ]
)

