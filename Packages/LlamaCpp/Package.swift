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
        .library(
            name: "LlamaCpp",
            targets: ["llama"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b9929/llama-b9929-xcframework.zip",
            checksum: "cc022885706276c40d99e2ad80dc564f1c14d32d4d7c4a310ab2683028a33b47"
        )
    ]
)
