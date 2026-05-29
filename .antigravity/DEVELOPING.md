# Developing GemmaEdgeGallery

This document outlines the core context and rules for developing the GemmaEdgeGallery application. Agents and subagents must read and adhere to these constraints.

## Project Specifications
- **Target OS:** iOS 26.5+ and macOS 12.0+
- **Language:** Swift 6.0+
- **Developer Team ID:** `ASX83B274M` (Free Personal Team)
- **Bundle ID Base:** `com.andrewvoirol.GemmaEdgeGallery`
- **Project Generator:** Tuist (Always edit `Project.swift`, never `.xcodeproj`)

## AI Model Payload (Gemma 4 LiteRT)
This app is designed to run Gemma 4 models on-device using the `LiteRT-LM` library.
- LLM weights are extremely large (~1.5GB+). 
- **File Name:** `gemma-4-E2B-it-web.litertlm` (or similar).
- **Storage:** The model file is currently located in the root of the project.
- **Handling:** For device execution, the model must be physically copied into the app's internal sandbox or appropriately scoped. Do not try to bundle a 1.5GB file directly into the app bundle during development as it will slow down build times drastically. Instead, use the iOS Document Picker or a script to push it to the simulator/device's App Documents directory.

## Build and Run Pipeline
1. Edit code in `Sources/` or `Project.swift`.
2. If `Project.swift` is edited, run `tuist generate`.
3. Build the app using `fastlane ios build` (for simulator/headless) or via Xcode (for physical device profiling).
