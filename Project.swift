// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import ProjectDescription
import Foundation

let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"

let project = Project(
    name: "GemmaEdgeGallery",
    options: .options(
        disableBundleAccessors: true,
        disableSynthesizedResourceAccessors: true
    ),
    packages: [
        // LiteRT-LM — Native Swift APIs with Metal GPU for macOS/iOS.
        // Uses .branch("main") to bypass SPM unsafeFlags restriction on tagged releases.
        // NOTE: .revision() doesn't work with this repo (SPM can't check out individual commits).
        // CI pre-clones the repo to work around GHA-specific SPM resolution failures.
        .remote(url: "https://github.com/google-ai-edge/LiteRT-LM.git", requirement: .branch("main")),
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
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json"],
            // Increased Memory Limit entitlement for large model inference.
            // NOTE: extended-virtual-addressing requires paid Apple Developer Program;
            // increased-memory-limit works with personal teams (matches zealous-bose config).
            entitlements: .file(path: "GemmaEdgeGallery_iOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM"),
                .package(product: "MarkdownUI")
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
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Edge AI Lab",
                "CFBundleName": "Edge AI Lab",
            ]),
            sources: ["Sources/**"],
            resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json"],
            entitlements: .file(path: "GemmaEdgeGallery_macOS.entitlements"),
            dependencies: [
                .package(product: "LiteRTLM"),
                .package(product: "MarkdownUI")
            ],
            settings: .settings(
                base: [
                    "PRODUCT_NAME": "Edge AI Lab",
                    "PRODUCT_MODULE_NAME": "GemmaEdgeGallery_macOS"
                ]
            )
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
            ],
            settings: .settings(
                base: [
                    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Edge AI Lab.app/Contents/MacOS/Edge AI Lab"
                ]
            )
        ),
        .target(
            name: "GemmaEdgeGallery_macOSUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac.UITests",
            deploymentTargets: .macOS("26.0"),
            infoPlist: .default,
            sources: ["UITests/**"],
            dependencies: [
                .target(name: "GemmaEdgeGallery_macOS")
            ],
            settings: .settings(
                base: [
                    "TEST_TARGET_NAME": "GemmaEdgeGallery_macOS"
                ]
            )
        ),
        .target(
            name: "GemmaEdgeGallery_iOSUITests",
            destinations: .iOS,
            product: .uiTests,
            bundleId: "com.andrewvoirol.GemmaEdgeGallery.UITests",
            deploymentTargets: .iOS("26.5"),
            infoPlist: .default,
            sources: ["iOSUITests/**"],
            dependencies: [
                .target(name: "GemmaEdgeGallery_iOS")
            ],
            settings: .settings(
                base: [
                    "TEST_TARGET_NAME": "GemmaEdgeGallery_iOS"
                ]
            )
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
                [
                    "GemmaEdgeGallery_iOSTests",
                    "GemmaEdgeGallery_iOSUITests"
                ],
                configuration: .debug,
                options: .options(coverage: true)
            ),
            runAction: .runAction(configuration: .debug)
        ),
        .scheme(
            name: "Edge AI Lab",
            shared: true,
            buildAction: .buildAction(targets: ["GemmaEdgeGallery_macOS"]),
            testAction: .targets(
                [
                    "GemmaEdgeGallery_macOSTests",
                    "GemmaEdgeGallery_macOSUITests"
                ],
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

