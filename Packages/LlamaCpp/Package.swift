// swift-tools-version: 6.0
// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Local SPM umbrella package for llama.cpp XCFramework.
//
// Downloads the prebuilt XCFramework directly from llama.cpp's official
// GitHub releases. No middleman wrapper — we own this integration.
//
// To update to a newer llama.cpp build:
// 1. Check latest: curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | jq .tag_name
// 2. Download: curl -LO https://github.com/ggml-org/llama.cpp/releases/download/bXXXX/llama-bXXXX-xcframework.zip
// 3. Checksum: swift package compute-checksum llama-bXXXX-xcframework.zip
// 4. Update url + checksum below
// 5. tuist generate → build → test

import PackageDescription

let package = Package(
    name: "LlamaCpp",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        // Expose the binary framework directly as the product.
        // The module name is "llama" (from the XCFramework's modulemap).
        // Use `import llama` in Swift source, `#if canImport(llama)` for guards.
        .library(
            name: "LlamaCpp",
            targets: ["LlamaCppBridge"]
        )
    ],
    targets: [
        // Thin bridge target that re-exports the binary framework.
        // This is needed because SPM doesn't allow a library product
        // to directly expose a binaryTarget in all configurations.
        .target(
            name: "LlamaCppBridge",
            dependencies: ["llama"],
            path: "Sources/LlamaCppBridge"
        ),
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b10076/llama-b10076-xcframework.zip",
            checksum: "eb1065dc416d32581009af84f947bd26a2c2d01aeadadb572aa4e23fe69a013c"
        )
    ]
)
