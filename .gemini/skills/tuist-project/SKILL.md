---
name: tuist-project
description: Manage the GemmaEdgeGallery Xcode project via Tuist — regenerate after manifest changes, add targets, update dependencies, and troubleshoot project generation issues. Use this skill when modifying Project.swift, adding targets or dependencies, or when the Xcode project needs to be regenerated.
---

# Tuist Project Management

This skill covers managing the GemmaEdgeGallery Xcode project using Tuist as the project generator.

## Key Principle

> **GemmaEdgeGallery uses `Project.swift` (Tuist), NOT `Package.swift` (SPM).** Never create or edit a `Package.swift` file. All project configuration is in `Project.swift`.

## Project Manifest Overview

The project manifest is at the repository root: `Project.swift`

```
Project: GemmaEdgeGallery
├── GemmaEdgeGallery_iOS         (iOS app)
├── GemmaEdgeGallery_iOSTests    (iOS unit tests)
├── GemmaEdgeGallery_macOS       (macOS app — "Edge AI Lab")
├── GemmaEdgeGallery_macOSTests  (macOS unit tests)
├── GemmaEdgeGallery_macOSUITests (macOS UI tests)
└── RawBenchmark                 (macOS CLI tool)
```

## Installing Tuist

The project pins Tuist to a specific version via `.mise.toml`. Install [mise](https://mise.run) first, then install Tuist:

```bash
# Install mise (skip if already installed)
curl https://mise.run | sh

# Install Tuist (version pinned by .mise.toml)
mise install
```

Verify installation:
```bash
tuist version
```

> **NOTE:** Do NOT install Tuist via `brew install tuist` — this installs an unpinned version that may produce different project generation results. Always use `mise install` to match the version in `.mise.toml`.

## Core Commands

### Generate the Xcode Project

```bash
cd /Users/andrewvoirol/Antigravity/Projects/gemma-edgegallery
tuist generate
```

This creates/updates:
- `GemmaEdgeGallery.xcodeproj`
- `GemmaEdgeGallery.xcworkspace`
- `Derived/` directory (generated Info.plist files only — bundle and asset accessors are disabled)

### Project Options

The project uses `options` to disable Tuist's code generation features that aren't used:

```swift
options: .options(
    disableBundleAccessors: true,
    disableSynthesizedResourceAccessors: true
)
```

This prevents Tuist from generating `TuistBundle+*.swift` and `TuistAssets+*.swift` files in `Derived/Sources/`. The app uses `Bundle.main` directly.

### Build Performance

The project enables Xcode 26 compilation caching at the project level:

```swift
"COMPILATION_CACHE_ENABLE_CACHING": "YES"
```

This provides sub-function-level caching via LLVM CAS, significantly speeding up branch switching and incremental builds.

### Clean Tuist Caches

```bash
tuist clean
```

Use when:
- Build settings seem stale
- Scheme changes aren't reflected
- SPM dependencies aren't resolving correctly

### Full Reset

```bash
tuist clean
rm -rf Derived/
tuist generate
```

## When to Regenerate

You MUST run `tuist generate` after:

| Change | Reason |
|---|---|
| Modified `Project.swift` | Any manifest change requires regeneration |
| Added/removed a target | New `.xcodeproj` targets needed |
| Changed dependencies | SPM package references need updating |
| Modified scheme configuration | Scheme definitions are in manifest |
| Changed entitlements file references | `.entitlements` paths are in manifest |
| Changed deployment targets | Min OS version is in manifest |
| Changed Info.plist entries | `infoPlist` config is in manifest |
| Changed build settings | Settings are in manifest |

You do NOT need to regenerate after:

| Change | Reason |
|---|---|
| Added/removed `.swift` files in `Sources/` | Uses `Sources/**` glob — auto-discovered |
| Added/removed `.swift` files in `Tests/` | Uses `Tests/**` glob — auto-discovered |
| Modified existing source files | No project structure change |
| Changed `.xctestplan` files | Test plans are independent of project generation |

## Targets

### GemmaEdgeGallery_iOS

```swift
.target(
    name: "GemmaEdgeGallery_iOS",
    destinations: .iOS,
    product: .app,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery",
    deploymentTargets: .iOS("26.5"),
    sources: ["Sources/**"],
    resources: ["Sources/Assets.xcassets"],
    entitlements: .file(path: "GemmaEdgeGallery_iOS.entitlements"),
    dependencies: [
        .package(product: "LiteRTLM"),
        .package(product: "MarkdownUI")
    ]
)
```

### GemmaEdgeGallery_macOS

```swift
.target(
    name: "GemmaEdgeGallery_macOS",
    destinations: .macOS,
    product: .app,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac",
    deploymentTargets: .macOS("26.0"),
    sources: ["Sources/**"],
    resources: ["Sources/Assets.xcassets"],
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
)
```

> **NOTE:** The macOS app is branded as "Edge AI Lab" via `PRODUCT_NAME` and `CFBundleDisplayName`, but the module name remains `GemmaEdgeGallery_macOS`. Import it as `@testable import GemmaEdgeGallery_macOS` in tests.

### GemmaEdgeGallery_iOSTests

```swift
.target(
    name: "GemmaEdgeGallery_iOSTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery.Tests",
    sources: ["Tests/**"],
    dependencies: [
        .target(name: "GemmaEdgeGallery_iOS")
    ]
)
```

### GemmaEdgeGallery_macOSTests

```swift
.target(
    name: "GemmaEdgeGallery_macOSTests",
    destinations: .macOS,
    product: .unitTests,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac.Tests",
    sources: ["Tests/**"],
    dependencies: [
        .target(name: "GemmaEdgeGallery_macOS")
    ],
    settings: .settings(
        base: [
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/Edge AI Lab.app/Contents/MacOS/Edge AI Lab"
        ]
    )
)
```

### GemmaEdgeGallery_macOSUITests

```swift
.target(
    name: "GemmaEdgeGallery_macOSUITests",
    destinations: .macOS,
    product: .uiTests,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery.mac.UITests",
    sources: ["UITests/**"],
    dependencies: [
        .target(name: "GemmaEdgeGallery_macOS")
    ],
    settings: .settings(
        base: [
            "TEST_TARGET_NAME": "GemmaEdgeGallery_macOS"
        ]
    )
)
```

### RawBenchmark

```swift
.target(
    name: "RawBenchmark",
    destinations: .macOS,
    product: .commandLineTool,
    bundleId: "com.andrewvoirol.GemmaEdgeGallery.RawBenchmark",
    deploymentTargets: .macOS("26.0"),
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
```

## Dependencies

### Current Dependencies

| Package | Source | Version | Used By |
|---|---|---|---|
| LiteRT-LM | `https://github.com/google-ai-edge/LiteRT-LM.git` | `branch: main` | iOS, macOS, RawBenchmark |
| MarkdownUI | `https://github.com/gonzalezreal/swift-markdown-ui.git` | `^2.0.0` | iOS, macOS |

### Why `branch: main` for LiteRT-LM

LiteRT-LM uses `unsafeFlags` in its `Package.swift`, which SPM forbids for tagged releases used as dependencies. Using `.branch("main")` bypasses this restriction. This means the dependency tracks the latest `main` commit.

### Adding a New Dependency

1. Add the package to `Project.swift`:
```swift
let project = Project(
    packages: [
        // Existing packages...
        .remote(url: "https://github.com/org/new-package.git", requirement: .upToNextMajor(from: "1.0.0"))
    ],
    // ...
)
```

2. Add it as a dependency to the relevant target(s):
```swift
.target(
    name: "GemmaEdgeGallery_iOS",
    // ...
    dependencies: [
        .package(product: "LiteRTLM"),
        .package(product: "MarkdownUI"),
        .package(product: "NewPackage")  // Add this
    ]
)
```

3. Regenerate:
```bash
tuist generate
```

## Schemes

### GemmaEdgeGallery_iOS

- **Build:** `GemmaEdgeGallery_iOS`
- **Test:** `GemmaEdgeGallery_iOSTests` (Debug, coverage enabled)
- **Run:** Debug configuration

### Edge AI Lab

- **Build:** `GemmaEdgeGallery_macOS`
- **Test:** `GemmaEdgeGallery_macOSTests` + `GemmaEdgeGallery_macOSUITests` (Debug, coverage enabled)
- **Run:** Debug configuration

### RawBenchmark

- **Build:** `RawBenchmark`
- **Run:** Release configuration (optimized for benchmarking)

## Source File Organization

### Automatic Inclusion via Globs

| Target | Source Glob | Description |
|---|---|---|
| iOS & macOS apps | `Sources/**` | All `.swift` files in Sources/ and subdirectories |
| iOS & macOS tests | `Tests/**` | All test files (shared between platforms) |
| macOS UI tests | `UITests/**` | macOS-specific UI test files |
| RawBenchmark | `RawBenchmark/**` | CLI benchmark tool sources |

### Adding a New Source File

Simply create a `.swift` file in the appropriate directory:
```bash
# App source (compiles for both iOS and macOS)
touch Sources/MyNewFeature.swift

# Test file (runs on both iOS simulator and macOS)
touch Tests/MyNewFeatureTests.swift

# macOS UI test
touch UITests/MyNewUITest.swift
```

No `tuist generate` needed — the glob patterns automatically pick up new files.

### Platform-Specific Code

Since `Sources/**` is shared between iOS and macOS targets, use `#if` for platform-specific code:

```swift
#if os(iOS)
import UIKit
// iOS-specific code
#elseif os(macOS)
import AppKit
// macOS-specific code
#endif
```

## Code Signing

The Team ID is set in the project-level settings with an environment variable override:

```swift
let teamId = ProcessInfo.processInfo.environment["DEVELOPMENT_TEAM"] ?? "Y7J7WUK693"

let project = Project(
    settings: .settings(
        base: [
            "DEVELOPMENT_TEAM": .string(teamId),
            "CODE_SIGN_STYLE": "Automatic"
        ]
    ),
    // ...
)
```

To build with a different team:
```bash
DEVELOPMENT_TEAM=YOUR_TEAM_ID tuist generate
```

## Common Issues & Fixes

### 1. SPM Cache Invalidation

**Symptom:** Old version of a dependency used, or `unable to resolve dependencies`

**Fix:**
```bash
tuist clean
rm -rf ~/Library/Developer/Xcode/DerivedData/GemmaEdgeGallery-*
rm -rf .build
tuist generate
```

### 2. Generated Files in Derived/

**Symptom:** Missing `Info.plist`

**Fix:** Info.plist files live in `Derived/InfoPlists/` which is created by `tuist generate`. If missing:
```bash
tuist generate
```

> **NOTE:** Bundle and asset accessors (`TuistBundle+*.swift`, `TuistAssets+*.swift`) are disabled via `disableBundleAccessors: true` and `disableSynthesizedResourceAccessors: true` in `Project.swift`. The app uses `Bundle.main` directly.

### 3. Scheme Not Found

**Symptom:** `xcodebuild: error: The scheme "Edge AI Lab" is not in the workspace`

**Fix:**
```bash
tuist generate
```
Then verify:
```bash
xcodebuild -workspace GemmaEdgeGallery.xcworkspace -list
```

### 4. "No such module" After Adding Dependency

**Symptom:** `error: No such module 'NewPackage'`

**Fix:** Ensure the dependency is added to BOTH the `packages` array AND the target's `dependencies` array in `Project.swift`, then:
```bash
tuist generate
```

### 5. Workspace File Conflicts

**Symptom:** Git conflicts in `.xcodeproj` or `.xcworkspace` files

**Fix:** These files are generated — don't manually resolve conflicts:
```bash
git checkout -- GemmaEdgeGallery.xcodeproj GemmaEdgeGallery.xcworkspace
tuist generate
```

### 6. Tuist Version Mismatch

**Symptom:** `Project.swift` uses APIs not available in installed Tuist version

**Fix:** Ensure you're using the version pinned in `.mise.toml`:
```bash
mise install
tuist generate
```

## Project Structure Reference

```
gemma-edgegallery/
├── Project.swift                      # ← Tuist manifest (THE source of truth)
├── .mise.toml                         # Tuist version pin (4.195.9)
├── GemmaEdgeGallery.xcworkspace/      # Generated by Tuist
├── GemmaEdgeGallery.xcodeproj/        # Generated by Tuist
├── Derived/                           # Generated by Tuist (Info.plists only)
│   └── InfoPlists/                    # Per-target Info.plist files
├── Sources/                           # App source (iOS + macOS, glob: Sources/**)
│   ├── Assets.xcassets                # Shared asset catalog
│   ├── DeveloperAutomationHarness.swift
│   ├── ConversationViewModel.swift
│   └── ...
├── Tests/                             # Unit tests (shared, glob: Tests/**)
│   ├── DownloadInfrastructureTests.swift
│   ├── ChatMessageTests.swift
│   └── ...
├── UITests/                           # macOS UI tests (glob: UITests/**)
├── iOSUITests/                        # iOS UI tests (glob: iOSUITests/**)
├── RawBenchmark/                      # CLI benchmark (glob: RawBenchmark/**)
├── GemmaEdgeGallery_iOS.entitlements  # iOS entitlements
├── GemmaEdgeGallery_macOS.entitlements # macOS entitlements
├── UnitTests.xctestplan               # Fast CI test plan
├── IntegrationTests.xctestplan        # Cross-component test plan
├── PerformanceTests.xctestplan        # Benchmark test plan
├── .github/
│   ├── actions/
│   │   └── setup-tuist-project/       # Composite action for CI preamble
│   └── workflows/
│       ├── ci.yml                     # Main CI workflow
│       └── benchmark.yml              # Benchmark CI workflow
└── automation/                        # CI scripts and flows
    ├── flows/                         # JSON automation flows
    ├── ci_test_runner.sh
    ├── run_matrix.py
    └── run_raw_benchmark.sh
```
