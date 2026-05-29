---
name: Fastlane Workflow
description: CI/CD batch building rules using Fastlane for the Gemma Edge Gallery project.
---

# Fastlane CI/CD Workflow

This project uses **Fastlane** for batch building, verification, and eventually test distribution.

## When to use Fastlane
Use Fastlane for comprehensive cross-platform compilation verification (e.g., ensuring both iOS and macOS targets compile successfully after major shared logic changes). 

## Available Lanes
The `fastlane/Fastfile` contains two primary lanes:
1. `fastlane ios build`
   - Generates the Tuist project.
   - Builds the `GemmaEdgeGallery_iOS` scheme for a generic iOS device.
2. `fastlane mac build`
   - Generates the Tuist project.
   - Builds the `GemmaEdgeGallery_macOS` scheme for macOS.

## Rules
- Do NOT use Fastlane to deploy apps to physical USB devices during rapid development; use the `XcodeBuildMCP` automation tools instead.
- Run Fastlane headlessly. If a keychain prompt or UI interaction is required, it will fail. Ensure provisioning profiles are cached before running iOS builds.
