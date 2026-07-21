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
        // Pinned to f73637c5 — v0.14.0 Swift source with updated checksums matching
        // Google's re-uploaded xcframework binaries. The v0.14.0 tag (80f301ff) has stale
        // checksums. Post-v0.14.0 commits added thinking config, repetition penalty, and
        // constrained decoding APIs that the v0.14.0 binary doesn't export.
        // When Google ships a new xcframework, advance this pin to the matching tag.
        // If SPM reports "invalid custom path 'swift'", nuke SourcePackages/checkouts/LiteRT-LM
        // + SourcePackages/repositories/LiteRT-LM-* and re-resolve.
        .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .revision("f73637c5")),
        // mlx-swift-lm: MLX inference (Apple Silicon Metal GPU) for macOS/iOS.
        // Pinned to commit d2424294 which includes all Gemma4 VLM fixes:
        //   - 09deb8c4: Fix VLM load KV-shared layers (k_proj/v_proj)
        //   - 68947ccd: Fix E-series num_kv_shared_layers
        //   - d14cf3da: Gemma tool parameter conversion by schema type
        //   - 2a2bdf4c: E-series MTP centroid embedder
        // Pin advance UNBLOCKED: mlx-swift 0.31.5 (Jun 30) and 0.31.6 (Jul 2) have shipped.
        // Advance past d2424294 to pick up MTP speculative decoding, FoundationModels bridge, etc.
        .remote(url: "https://github.com/ml-explore/mlx-swift-lm.git", requirement: .revision("d2424294a6c3")),
        // swift-transformers: HuggingFace tokenizers + Hub client for MLX model downloading.
        .remote(url: "https://github.com/huggingface/swift-transformers.git", requirement: .upToNextMajor(from: "1.1.1")),
        // MarkdownUI: Premium markdown rendering (lists, tables, blockquotes).
        .remote(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", requirement: .upToNextMajor(from: "2.0.0")),
        // LlamaCpp: llama.cpp XCFramework for GGUF model inference (Metal GPU).
        // Local umbrella package — downloads prebuilt XCFramework from official llama.cpp releases.
        // See Packages/LlamaCpp/Package.swift for version pinning and update instructions.
        .local(path: "Packages/LlamaCpp")
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
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json", "Tests/Resources/images/**", "Tests/Resources/audio/**"],
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
                .package(product: "LlamaCpp")          // llama.cpp GGUF inference
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
            resources: ["Tests/Resources/**", "automation/flows/**/*.json"],
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
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json", "Tests/Resources/images/**", "Tests/Resources/audio/**"],
            entitlements: .file(path: "EdgeAILab_macOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM"),
                .package(product: "MLXLLM"),
                .package(product: "MLXLMCommon"),
                .package(product: "MLXVLM"),         // Phase 4, add now to avoid re-gen
                .package(product: "Tokenizers"),     // HuggingFace tokenizer loading
                .package(product: "Hub"),             // HuggingFace Hub download client
                .package(product: "MarkdownUI"),
                .package(product: "LlamaCpp")          // llama.cpp GGUF inference
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
            resources: ["Tests/Resources/**", "automation/flows/**/*.json"],
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
            sources: ["UITests/**", "SharedTestSupport/**"],
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
            sources: ["iOSUITests/**", "SharedTestSupport/**"],
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
                ["iOSUnitTests.xctestplan", "iOSUITests.xctestplan", "SimulatorTests.xctestplan", "IntegrationTests.xctestplan", "PerformanceTests.xctestplan"],
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
            name: "Edge AI Lab (Release)",
            shared: true,
            buildAction: .buildAction(targets: ["EdgeAILab_macOS"]),
            runAction: .runAction(configuration: .release)
        ),
        .scheme(
            name: "RawBenchmark",
            shared: true,
            buildAction: .buildAction(targets: ["RawBenchmark"]),
            runAction: .runAction(configuration: .release)
        )
    ]
)

