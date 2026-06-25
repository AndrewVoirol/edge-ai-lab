# Testing — Canonical Matrix Definition

> **This document is the single source of truth for "run the full matrix."**
> The `automation/run_full_matrix.sh` script implements this definition.
> If they diverge, this document wins and the script gets fixed.

## Quick Reference

```bash
# Run everything (requires connected iPhone + local models)
bash automation/run_full_matrix.sh

# Run without device (Tiers 0–3 only)
bash automation/run_full_matrix.sh --skip-device

# Run unit tests only
bash automation/run_full_matrix.sh --only-unit
```

## Matrix Overview

| Tier | Name | Platform | Model Needed? | Critical? | Approx. Time |
|------|------|----------|:---:|:---:|:---:|
| 0a | Device Health Check | Device | ✗ | Gate | 30s |
| 0b | Flow JSON Validation | Local | ✗ | Gate | 5s |
| 1a | macOS Unit Tests | macOS | ✗ | ✓ | 10s |
| 1b | iOS Simulator Unit Tests | Sim | ✗ | ✓ | 60s |
| 2a | macOS UI Tests | macOS | ✗ | ✓ | 15m |
| 2b | macOS Automation Harness | macOS | ✗ | ✓ | 2m |
| 2c | iOS Simulator UI Tests | Sim | ✗ | ✓ | 13m |
| 2d | iOS Device UI Tests | Device | ✗ | ✓ | 15m |
| 3a | macOS Integration Tests | macOS | ✓ | ✓ | 10m |
| 3b | macOS Performance Tests | macOS | ✓ | ○ | 10m |
| 4a | iOS Device Benchmark | Device | ✓ | ○ | 15m+ |
| 4b | iOS Device Eval | Device | ✓ | ○ | 10m |
| 5a | Benchmark Regression Check | Local | ✗† | ○ | 5s |
| 5b | Cross-Platform Eval Report | Local | ✗† | ○ | 10s |

**Key:** ✓ = must pass for green, ○ = informational (failures noted but not blocking),
✗† = requires output from Tier 4 steps

---

## Prerequisites for Walk-Away Execution

The full matrix takes ~90 minutes. To run truly unattended, complete **all** of these once:

### 1. macOS: Disable Automation Mode Authentication (one-time, survives reboots)

macOS requires Touch ID / password to authorize XCUITest runner binaries for UI automation.
By default, this prompt returns **after every rebuild** because macOS keys the authorization
to the binary's absolute path in DerivedData, which changes on each build.

**Permanent fix** — run once in Terminal (requires your login password):
```bash
automationmodetool enable-automationmode-without-authentication
```
This disables the per-binary authentication globally. Survives reboots. No further prompts
for any UI test, ever. To re-enable authentication later:
```bash
automationmodetool disable-automationmode-without-authentication
```

### 2. iOS Device: Enable UI Automation (one-time, persists across reboots)

Physical device UI tests (Tier 2d) require the **Enable UI Automation** toggle on the iPhone.
The device passcode is requested when first enabling this — it is NOT an auto-lock issue.

**Setup** — do once on the physical device:
1. **Settings → Privacy & Security → Developer Mode** → toggle ON (restart required)
2. **Settings → Developer → Enable UI Automation** → toggle ON (passcode required to confirm)

Both settings persist across reboots. No further prompts unless you disable them.

### 3. iOS Device: Disable Auto-Lock (per-session)

If the iPhone screen locks during a long Tier 4a/4b pipeline (15-90 min), the deploy script
cannot interact with the device.

**Setup** — before each test session:
- **Settings → Display & Brightness → Auto-Lock → Never**
- Re-enable after testing to preserve battery.

### 4. macOS: Documents Folder Access (one-time, persists across rebuilds)

The Edge AI Lab app accesses `~/Documents` during startup (model and eval history discovery).
macOS prompts for folder access the first time.

**Trigger**: The app's own initialization code calls `FileManager.default.urls(for: .documentDirectory)`.
**Persistence**: Keyed by bundle ID (`com.andrewvoirol.EdgeAILab.mac`), not binary path.
Survives rebuilds and reboots. Only re-prompts after a clean OS install or TCC database reset.

**Fix**: Click "Allow" when prompted. One-time.

---

## Tier Definitions

### Tier 0 — Pre-flight Gates

Quick checks that catch broken prerequisites before expensive test runs.

#### 0a: Device Health Check
```bash
bash automation/device_health_check.sh [DEVICE_ID]
```
- **Checks**: Device connection, DDI services, app installation, XCTRunner, quick launch
- **Pass criteria**: All 5 checks green (app installation check is allowed to be ⚠️ before first build)
- **Dependencies**: Physical device connected via USB

#### 0b: Flow JSON Validation
```bash
bash automation/validate_flows.sh
```
- **Checks**: Syntax, required fields, known action types, step numbering for all 33 flow JSON files
- **Pass criteria**: 0 failures (warnings about optional fields are acceptable)
- **Dependencies**: None

---

### Tier 1 — Unit Tests (no model needed)

Fast, deterministic tests that verify logic without GPU or model dependencies.

#### 1a: macOS Unit Tests
```bash
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme "Edge AI Lab" -testPlan UnitTests \
    -destination "platform=macOS" \
    -only-testing:EdgeAILab_macOSTests
```
- **Scope**: ~2,000 tests in `EdgeAILab_macOSTests`
- **Test plan exclusions** (7 classes): `BatchEvalTests`, `GalleryParityBenchmarkTests`, `InferenceQualityTests`, `MetricsStoreTests`, `MultiTurnIntegrationTests`, `PerformanceTests`, `SmartFallbackIntegrationTests`
- **Pass criteria**: 0 failures

#### 1b: iOS Simulator Unit Tests
```bash
# Via MCP:
test_sim: { extraArgs: ["-testPlan", "SimulatorTests", "-only-testing:EdgeAILab_iOSTests"] }

# Via xcodebuild:
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme EdgeAILab_iOS -testPlan SimulatorTests \
    -destination "platform=iOS Simulator,name=iPhone 16 Pro Max" \
    -only-testing:EdgeAILab_iOSTests
```
- **Scope**: ~2,000 tests in `EdgeAILab_iOSTests`
- **Test plan exclusions**: `InferenceQualityTests` (requires real Metal GPU)
- **Expected skips**: ~39 tests (XCTSkip for platform-specific or resource-dependent)
- **Pass criteria**: 0 failures

---

### Tier 2 — UI Tests (no model needed)

Flow-driven UI tests using XCUITest. **Never run concurrent UI test processes** — they share the screen, keyboard, and accessibility session.

#### 2a: macOS UI Tests
```bash
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme "Edge AI Lab" -testPlan macOSUITests \
    -destination "platform=macOS" \
    -only-testing:EdgeAILab_macOSUITests/EdgeAILabUITests
```
- **Scope**: 10 flow-driven tests
- **Known requirement**: Cmd+N retry after launch (up to 3 attempts, 2s/3s/4s delays)
- **Pass criteria**: 0 failures
- **Constraint**: Must complete before 2c or 2d start

#### 2b: macOS Automation Harness
```bash
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme "Edge AI Lab" -testPlan macOSUITests \
    -destination "platform=macOS" \
    -only-testing:EdgeAILab_macOSUITests/AutomationHarnessXCTests
```
- **Scope**: 4 tests validating the automation harness CLI argument parsing and flow dispatch
- **Pass criteria**: 0 failures

#### 2c: iOS Simulator UI Tests
```bash
# Via MCP:
test_sim: { extraArgs: ["-testPlan", "iOSUITests", "-only-testing:EdgeAILab_iOSUITests"] }
```
- **Scope**: 13 flow-driven tests + DynamicTypeTests
- **Pass criteria**: 0 failures
- **Constraint**: Must not overlap with 2a or 2d

#### 2d: iOS Device UI Tests
```bash
# Via MCP:
test_device: { extraArgs: ["-testPlan", "iOSUITests", "-only-testing:EdgeAILab_iOSUITests"] }
```
- **Scope**: Same flows as 2c but on physical device
- **Known transient**: "Timed out while enabling automation mode" — retry once
- **Pass criteria**: 0 failures
- **Dependencies**: App must be installed on device

---

### Tier 3 — Model-Dependent Tests (real GPU required)

Integration tests that load real AI models and run real inference. Requires `.litertlm` model files in the project's `models/` directory.

#### 3a: macOS Integration Tests
```bash
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme "Edge AI Lab" -testPlan macOSIntegrationTests \
    -destination "platform=macOS"
```
- **Scope**: `InferenceQualityTests` + `SmartFallbackIntegrationTests`
- **Models**: Uses `models/gemma-4-E2B-it.litertlm` or `models/gemma-4-E4B-it-web.litertlm`
- **Timeout**: 300s per test
- **Pass criteria**: 0 failures (or XCTSkip if model not found)

#### 3b: macOS Performance Tests
```bash
xcodebuild test -workspace EdgeAILab.xcworkspace \
    -scheme "Edge AI Lab" -testPlan macOSPerformanceTests \
    -destination "platform=macOS"
```
- **Scope**: `PerformanceTests` + `SmartFallbackIntegrationTests`
- **Timeout**: 600s per test
- **Pass criteria**: 0 failures (or XCTSkip if model not found)

---

### Tier 4 — Device Pipelines (Release build, physical device)

Automation harness-driven pipelines that exercise real inference on the iPhone's GPU.

#### 4a: iOS Device Benchmark Pipeline
```bash
env BUILD_CONFIG=Release CONSOLE_TIMEOUT=5400 \
    bash automation/deploy_device.sh DEVICE_ID -RunBenchmarkPipeline
```
- **What it does**: Release build → install → launch → download model if needed → run benchmark → pull results
- **Output**: `metrics/benchmark-results.jsonl`
- **Timeout**: 5400s (90 min) to allow for model download
- **Pass criteria**: Pipeline completes, `benchmark-results.jsonl` contains data entries (not just warmup)

#### 4b: iOS Device Eval Pipeline
```bash
env BUILD_CONFIG=Release SKIP_BUILD=1 CONSOLE_TIMEOUT=3600 \
    bash automation/deploy_device.sh DEVICE_ID -RunEvalPipeline
```
- **What it does**: Reuse Release build → launch → run eval suites → pull results
- **Output**: `Documents/eval_results/index.json` on device (pulled to `metrics/device_eval_pull/`)
- **Pass criteria**: Pipeline completes, eval results contain suite scores

---

### Tier 5 — Reporting (post-execution analysis)

#### 5a: Benchmark Regression Check
```bash
bash automation/benchmark_compare.sh --results metrics/benchmark-results.jsonl
```
- **What it does**: Compares benchmark results against `metrics/baselines.json`
- **Output**: `regression_report.json`
- **Pass criteria**: Report contains non-zero comparisons (not vacuous "no regressions")

#### 5b: Cross-Platform Eval Report
```bash
bash automation/eval_comparison.sh --device DEVICE_ID
```
- **What it does**: Merges macOS eval history + iOS device eval results → `CROSS_PLATFORM_REPORT.md`
- **Pass criteria**: iOS columns show actual scores (not "—")

---

## Execution Rules

1. **No concurrent xcodebuild UI test processes.** Tiers 2a, 2c, and 2d must run sequentially.
2. **Model download can take 60+ minutes.** Start Tier 4a early if possible.
3. **Device pipelines use Release builds.** Tier 4 builds take longer than Debug.
4. **Test plan exclusions are not skips.** The 7 classes excluded by `UnitTests.xctestplan` are covered by Tier 3.
5. **"Green" means zero failures.** No expected failures, no vacuous passes, no "—" columns.

## Glossary

| Term | Meaning |
|------|---------|
| **Full matrix** | All tiers 0–5 run, all passing, all producing real data |
| **Test pyramid** | Synonym for full matrix (unit → UI → integration → device) |
| **Green run** | Every test passes, every script produces populated output |
| **Dry-run** | Pipeline validates plumbing without real inference (uses `-DryRun` launch arg) — NOT a substitute for a real run |
