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
- Never commit model files to git (they are 1.5-2GB each)
- See `.antigravity/skills/performance-testing/scripts/provision-model.sh` for availability checks

## Dependencies
- Swift package dependencies are declared in `Project.swift`
- `.package.resolved` is committed for dependency locking
- The only external dependency is `LiteRT-LM` from google-ai-edge
