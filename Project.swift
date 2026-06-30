// Copyright 2026 Andrew Voirol. Apache-2.0

import ProjectDescription
import Foundation

let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"

let project = Project(
    name: "EdgeAILab",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        // LiteRT-LM — Native Swift APIs with Metal GPU for macOS/iOS.
        // Uses .branch("main") to bypass SPM unsafeFlags restriction on tagged releases.
        // NOTE: .revision() doesn't work with this repo (SPM can't checkout custom paths).
        // CI pre-clones the repo to work around GHA-specific SPM resolution failures.
        .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .branch("main")),
        // mlx-swift-lm: MLX inference (Apple Silicon Metal GPU) for macOS/iOS.
        // Tracks main branch (consistent with LiteRT-LM strategy).
        .remote(url: "https://github.com/ml-explore/mlx-swift-lm.git", requirement: .branch("main")),
        // swift-transformers: HuggingFace tokenizers + Hub client for MLX model downloading.
        .remote(url: "https://github.com/huggingface/swift-transformers.git", requirement: .upToNextMajor(from: "1.1.1")),
        // MarkdownUI: Premium markdown rendering (lists, tables, blockquotes).
        .remote(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", requirement: .upToNextMajor(from: "2.0.0"))
    ],
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": .string(teamId),
            "CODE_SIGN_STYLE": "Automatic",
            "COMPILATION_CACHE_ENABLE_CACHING": "YES"
        ]
    ),
    targets: [
        .target(
            name: "EdgeAILab_iOS",
            destinations: .iOS,
            product: .app,
            bundleId: "com.andrewvoirol.EdgeAILab",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Edge AI Lab",
                "UILaunchScreen": [:],
                // Enable iTunes/Finder file sharing so models can be copied to Documents/
                "UIFileSharingEnabled": true,
                // Allow the Files app to browse and manage model files in Documents/
                "LSSupportsOpeningDocumentsInPlace": true,
                // Support opening .litertlm files directly from other apps
                "UISupportsDocumentBrowser": true,
                // Location permission for the get_location tool
                "NSLocationWhenInUseUsageDescription": "Edge AI Lab uses your location to provide context-aware responses when you ask location-related questions.",
            ]),
            sources: ["Sources/**"],
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json", "Tests/Resources/images/**"],
            // Increased Memory Limit entitlement for large model inference.
            // NOTE: extended-virtual-addressing requires paid Apple Developer Program;
            // increased-memory-limit works with personal teams (matches zealous-bose config).
            entitlements: .file(path: "EdgeAILab_iOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM"),
                .package(product: "MLXLLM"),
                .package(product: "MLXLMCommon"),
                .package(product: "MLXVLM"),         // Phase 4, add now to avoid re-gen
                .package(product: "Tokenizers"),     // HuggingFace tokenizer loading
                .package(product: "Hub"),             // HuggingFace Hub download client
                .package(product: "MarkdownUI"),
                .sdk(name: "CloudKit", type: .framework)
            ]
        ),
        .target(
            name: "EdgeAILab_iOSTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.andrewvoirol.EdgeAILab.Tests",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            resources: ["Tests/Resources/**"],
            dependencies: [
                .target(name: "EdgeAILab_iOS")
            ]
        ),
        .target(
            name: "EdgeAILab_macOS",
            destinations: .macOS,
            product: .app,
            bundleId: "com.andrewvoirol.EdgeAILab.mac",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Edge AI Lab",
                "CFBundleName": "Edge AI Lab",
                // Location permission for the get_location tool
                "NSLocationUsageDescription": "Edge AI Lab uses your location to provide context-aware responses when you ask location-related questions.",
            ]),
            sources: ["Sources/**"],
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json", "Tests/Resources/images/**"],
            entitlements: .file(path: "EdgeAILab_macOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM"),
                .package(product: "MLXLLM"),
                .package(product: "MLXLMCommon"),
                .package(product: "MLXVLM"),         // Phase 4, add now to avoid re-gen
                .package(product: "Tokenizers"),     // HuggingFace tokenizer loading
                .package(product: "Hub"),             // HuggingFace Hub download client
                .package(product: "MarkdownUI"),
                .sdk(name: "CloudKit", type: .framework)
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "Edge AI Lab",
                    "PRODUCT_MODULE_NAME": "EdgeAILab_macOS"
                ]
            )
        ),
        .target(
            name: "EdgeAILab_macOSTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.andrewvoirol.EdgeAILab.mac.Tests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["Tests/**"],
            resources: ["Tests/Resources/**"],
            dependencies: [
                .target(name: "EdgeAILab_macOS")
            ],
            settings: .settings(
                base: [
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Edge AI Lab.app/Contents/MacOS/Edge AI Lab"
                ]
            )
        ),
        .target(
            name: "EdgeAILab_macOSUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.andrewvoirol.EdgeAILab.mac.UITests",
            deploymentTargets: .macOS("27.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            resources: ["automation/flows/**/*.json"],
            dependencies: [
                .target(name: "EdgeAILab_macOS")
            ],
            settings: .settings(
                base: [
                    "TEST_TARGET_NAME": "EdgeAILab_macOS"
                ]
            )
        ),
        .target(
            name: "EdgeAILab_iOSUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.andrewvoirol.EdgeAILab.UITests",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .default,
            sources: ["iOSUITests/**"],
            resources: ["automation/flows/**/*.json"],
            dependencies: [
                .target(name: "EdgeAILab_iOS")
            ],
            settings: .settings(
                base: [
                    "TEST_TARGET_NAME": "EdgeAILab_iOS"
                ]
            )
        ),
        .target(
            name: "RawBenchmark",
            destinations: .macOS,
            product: .commandLineTool,
            bundleId: "com.andrewvoirol.EdgeAILab.RawBenchmark",
            deploymentTargets: .macOS("27.0"),
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
            name: "EdgeAILab_iOS",
            shared: true,
            buildAction: .buildAction(targets: ["EdgeAILab_iOS"]),
            testAction: .testPlans(
                ["UnitTests.xctestplan", "iOSUITests.xctestplan", "SimulatorTests.xctestplan", "IntegrationTests.xctestplan", "PerformanceTests.xctestplan"],
                configuration: .debug
            ),
            runAction: .runAction(configuration: .debug)
        ),
        .scheme(
            name: "Edge AI Lab",
            shared: true,
            buildAction: .buildAction(targets: ["EdgeAILab_macOS"]),
            testAction: .testPlans(
                ["UnitTests.xctestplan", "macOSUITests.xctestplan", "macOSIntegrationTests.xctestplan", "macOSPerformanceTests.xctestplan"],
                configuration: .debug
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

