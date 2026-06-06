# Project Structure Invariants

These constraints protect the project from structural corruption.

## Generated Artifacts — DO NOT EDIT
- **NEVER** directly edit `GemmaEdgeGallery.xcodeproj/` — it is Tuist-generated
- **NEVER** directly edit `GemmaEdgeGallery.xcworkspace/` — it is Tuist-generated  
- **NEVER** directly edit anything in `Derived/` — it is Tuist-generated
- ALL project configuration changes go through `Project.swift` → `tuist generate`

## Source Layout
- Source code: `Sources/` (Swift files)
- Tests: `Tests/` (Swift test files)
- Project config: `Project.swift` (Tuist manifest)
- Agent config: `.antigravity/` (skills, rules, hooks, DEVELOPING.md)

## Model Files
- Model files (`*.litertlm`) live in `models/` directory
- `models/` is gitignored — models are locally provisioned, not committed
- Never commit model files to git (they are 2.0-6.5GB each)
- Current models: Gemma 4 E2B (Standard + Web), E4B (Standard + Web), **12B Dense Multimodal (new)**
- See `.antigravity/skills/performance-testing/scripts/provision-model.sh` for availability checks

### Physical Device Provisioning
Models must be pushed to the app's Documents/ directory on the device:
```bash
xcrun devicectl device copy to --device <UDID> \
  --domain-type appDataContainer \
  --domain-identifier com.andrewvoirol.GemmaEdgeGallery \
  --source models/<filename>.litertlm \
  --destination Documents/<filename>.litertlm
```

> [!NOTE]
> The iOS target includes `UIFileSharingEnabled`, `LSSupportsOpeningDocumentsInPlace`, and `UISupportsDocumentBrowser` in its InfoPlist (configured in `Project.swift`). This enables model files to be copied via Finder, AirDrop, or the Files app.

## Dependencies
- Swift package dependencies are declared in `Project.swift`
- `.package.resolved` is committed for dependency locking
- The only external dependency is `LiteRT-LM` from google-ai-edge (pinned to `main` branch, current HEAD: `aeefa9b`)
- SDK version: `0.13.0-dev` — v0.12.0 tag has SPM packaging issues (Issue #2407)
