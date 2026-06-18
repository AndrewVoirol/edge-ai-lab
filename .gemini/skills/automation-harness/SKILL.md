---
name: automation-harness
description: Trigger and parse the DeveloperAutomationHarness for in-app E2E testing and benchmarking via JSON automation flows. Use this skill for running benchmark flows, model setup automation, inference testing, and CI pipeline integration.
---

# Automation Harness

This skill covers the `DeveloperAutomationHarness` — an in-app automation system that runs benchmark and E2E test flows via launch arguments, outputting structured results to stdout.

## Dual-Path Automation Architecture

The project uses two complementary automation paths that share the same flow JSON definitions:

| | Path 1: In-App Self-Inspection | Path 2: External Test Runner (XCUITest Bridge) |
|---|---|---|
| **How it works** | App loads flow JSONs and inspects its own UI via `AccessibilityTreeInspector` | XCUITest process loads same flow JSONs and performs real `XCUIElement` queries from outside |
| **Implementation** | `AutomationFlowRunner` + `AccessibilityTreeInspector` | `FlowDrivenUITestRunner` + `XCUIElement` queries |
| **Runs via** | Launch args: `-RunFlow`, `-RunAllFlows`, `-RunBenchmarkPipeline` | `xcodebuild test` targeting `EdgeAILab_macOSUITests` |
| **Best for** | On-device testing, benchmarking, CI without XCUITest | CI regression testing, UI automation, screenshot capture |
| **Platform** | macOS + iOS (in-process) | macOS + iOS Simulator (out-of-process) |

> **Single source of truth**: Both paths consume the same flow JSON files from `automation/flows/`. Write one flow, run it both ways.

> **iOS Note**: The flow runner uses `AccessibilityTreeInspector` for in-process a11y inspection, but the XCUITest bridge runs out-of-process using `XCUIElement` queries. Both are preserved because they serve different purposes — flows run in-app for device testing, the bridge runs in XCUITest for CI.

## When to Use This vs XCTest

| Use XCTest when... | Use the Automation Harness when... |
|---|---|
| Unit/integration tests (fast, isolated) | E2E user journeys (model download → inference → verify) |
| Testing ViewModel logic | Benchmarking (TTFT, decode speed, memory) |
| Regression checks on every PR | Matrix configurations (GPU/CPU/MTP combinations) |
| Speed matters (418 tests in 3.4s) | Full app lifecycle with real models |

> **NOTE:** On-device XCTest works correctly (the previous hang was caused by PhaseAnimator runloop saturation, now fixed). Use XCTest for unit/integration tests. Use the harness for E2E flows and benchmarks.

## Flow Bundling

Automation flow JSONs are bundled as app resources via `Project.swift`:
```swift
resources: ["Sources/Assets.xcassets", "automation/flows/**/*.json"]
```

The `AutomationFlowRunner.flowsDirectory()` method uses a 4-tier lookup:
1. Bundle subdirectory: `Bundle.main.url(forResource: "flows", subdirectory: "automation")`
2. Bundle root `/flows` directory
3. Glob-bundled files in bundle root (checks for `benchmark_flow.json`)
4. Development fallback: project `automation/flows/` directory

## Launch Arguments

The harness activates based on these command-line arguments:

### Flow & Test Arguments

| Argument | Description |
|---|---|
| `-RunAllTests` | Full single-model benchmark: wipe models → download Gemma 4 E2B → GPU init → warmup → benchmark → report |
| `-RunMatrixBenchmark` | Multi-configuration matrix: runs 10 config combinations across models/GPU/CPU/MTP/sampling |
| `-RunMatrixBenchmark N` | Run only configuration N (1-indexed) from the matrix |
| `-RunFlow <name>` | Run a specific JSON automation flow from `automation/flows/` |
| `-RunAllFlows` | Run all discovered automation flows in sequence |
| `-ListFlows` | List all available automation flows and exit |

### Pipeline Arguments

| Argument | Description | When to Use |
|---|---|---|
| `-RunBenchmarkPipeline` | Discover models → benchmark → compare against baselines → report regressions | Self-hosted CI runners with pre-staged models |
| `-RunEvalPipeline` | Load built-in eval suites → run against models → report scored results | Self-hosted CI or manual eval validation |

### Modifiers

| Modifier | Description | When to Use |
|---|---|---|
| `-DryRun` | Skip real UI assertions and model inference; validate pipeline plumbing only | CI runners without models or GPU. Combine with any `-Run*` argument |
| `-EvalGated` | Enable threshold-based eval CI gating. Fails with exit code 1 on critical eval regressions | Release/schedule CI jobs that should block on eval quality drops |

### Validation

| Argument | Description | When to Use |
|---|---|---|
| `-RunValidation` | Run internal benchmarking subsystem validation checks and display PASS/FAIL results | Verifying MetricsStore, DeviceMetrics, baselines, regression checker, and eval suites work correctly |

## Available Automation Flows

Located in `automation/flows/`:

| Flow File | Name | Purpose |
|---|---|---|
| `benchmark_flow.json` | Performance Benchmarks & Metrics Capture | Select model → warmup → benchmark prompt → capture TTFT/Decode/Memory metrics |
| `inference_flow.json` | Chat & Inference Flow | Select model → type prompt → generate → verify response with TTFT/Decode |
| `model_setup_flow.json` | Model Setup & HF Token Configuration | Verify UI → open Settings → enter HuggingFace token → close settings |
| `multimodal_flow.json` | Multimodal Inference Flow | Attach image → type prompt → generate multimodal response → verify |
| `settings_flow.json` | Settings Verification Flow | Open settings → toggle MTP → test Greedy/Default presets → set system message |
| `e2e_regression_flow.json` | E2E Regression Flow | Full app lifecycle: verify UI → select model → prompt → wait for response → verify metrics |

### UI Flow JSONs (XCUITest Bridge)

Located in `automation/flows/ui/` — consumed by `FlowDrivenUITestRunner` in the XCUITest bridge:

| Flow File | Name | Platform | Steps |
|---|---|---|---|
| `macos_basic_navigation_flow.json` | macOS Basic Navigation | macOS | 7 |
| `macos_settings_flow.json` | macOS Settings Interactions | macOS | 12 |
| `macos_sidebar_flow.json` | macOS Sidebar Structure | macOS | 9 |
| `macos_input_area_flow.json` | macOS Input Area Components | macOS | 6 |
| `macos_chat_interactions_flow.json` | macOS Chat Interactions | macOS | 6 |
| `macos_quick_actions_flow.json` | macOS Quick Actions | macOS | 5 |
| `macos_mcp_server_flow.json` | macOS MCP Server Management | macOS | 9 |
| `macos_menu_commands_flow.json` | macOS Menu Commands | macOS | 6 |
| `macos_url_import_flow.json` | macOS URL Import | macOS | 11 |
| `macos_community_browser_flow.json` | macOS Community Models Browser | macOS | 12 |
| `ios_smoke_flow.json` | iOS Smoke Tests | iOS | 12 |

## Flow JSON Format

Each flow file follows this schema:

```json
{
  "name": "Human-readable flow name",
  "description": "Optional description",
  "prerequisites": ["Optional list of prerequisites"],
  "steps": [
    {
      "step": 1,
      "action": "verify_ui",
      "description": "Human-readable step description",
      "expected_elements": ["Element1", "Element2"],
      "assertion": {
        "type": "element_value_contains",
        "element": "Element1",
        "expected": "expected substring"
      }
    },
    {
      "step": 2,
      "action": "tap",
      "description": "Tap a button or element",
      "target_element": "Button Label"
    },
    {
      "step": 3,
      "action": "type_text",
      "description": "Enter text into a field",
      "target_element": "Text Field Identifier",
      "value": "Text to type"
    },
    {
      "step": 4,
      "action": "wait",
      "description": "Wait for a condition",
      "condition": "element_not_exists:Generating..."
    }
  ]
}
```

### Post-Step Assertions

Steps can include an optional `assertion` field for post-step verification:

| Type | Fields | Description |
|---|---|---|
| `element_exists` | `element` | Assert that an element with the given identifier exists |
| `element_value_contains` | `element`, `expected` | Assert the element's value contains the expected substring |
| `element_value_equals` | `element`, `expected` | Assert the element's value exactly equals the expected string |

### Supported Actions

| Action | Required Fields | Description |
|---|---|---|
| `verify_ui` | `expected_elements` | Assert that all listed accessibility elements exist on screen |
| `tap` | `target_element` | Tap the element matching the given accessibility label |
| `type_text` | `target_element`, `value` | Focus the field and type the given text |
| `wait` | `condition` | Wait until the condition is met |

### Wait Conditions

| Condition | Format | Description |
|---|---|---|
| Element disappears | `element_not_exists:Label` | Wait until the element with the given label is no longer present |
| Element appears | `element_exists:Label` | Wait until the element with the given label appears |

### Environment Variable Interpolation

Flow values support `$ENV_VAR` syntax. The harness replaces these with environment variable values at runtime:

```json
{
  "action": "type_text",
  "target_element": "HuggingFace Token Field",
  "value": "$HF_TOKEN"
}
```

Set the environment variable before launching:
```bash
export HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

## Launching the Harness

### On Simulator

```bash
# Build first
xcodebuild build \
  -workspace EdgeAILab.xcworkspace \
  -scheme EdgeAILab_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet

# Launch with console output
xcrun simctl launch --console booted com.andrewvoirol.EdgeAILab -- -RunAllTests
```

```bash
# Run a specific flow
xcrun simctl launch --console booted com.andrewvoirol.EdgeAILab -- -RunFlow benchmark_flow
```

### On Physical Device

```bash
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  --console \
  com.andrewvoirol.EdgeAILab \
  -- -RunAllTests
```

### Via MCP

**Simulator:**
```
Tool: xcodebuild-mcp → launch_app_sim
Arguments:
  simulator: "iPhone 16 Pro"
  bundle_id: "com.andrewvoirol.EdgeAILab"
  arguments: ["-RunAllTests"]
```

**Device:**
```
Tool: xcodebuild-mcp → launch_app_device
Arguments:
  device: "Phactivity Monitor"
  bundle_id: "com.andrewvoirol.EdgeAILab"
  arguments: ["-RunFlow", "inference_flow"]
```

## Output Protocol

The harness writes structured output to stdout with these prefixes:

### Progress Lines

```
[AUTOMATION] Developer Automation Harness activated.
[AUTOMATION] -RunAllTests detected. Wiping all local models from Documents...
[AUTOMATION] Removed: gemma4-e2b-it-q8_0.litertlm
[AUTOMATION] Local models wiped. Discovered count: 0
[AUTOMATION] Downloading gemma4-e2b-it-q8_0.litertlm directly to iPhone...
[AUTOMATION] Download progress (gemma4-e2b-it-q8_0.litertlm): 45%
[AUTOMATION] gemma4-e2b-it-q8_0.litertlm downloaded successfully.
[AUTOMATION] Loading model gemma4-e2b-it-q8_0.litertlm on GPU...
[AUTOMATION] Resetting conversation...
[AUTOMATION] Running warmup turn (priming counters)...
[AUTOMATION] Running benchmark turn (decodes capped at 256)...
[AUTOMATION] Benchmark turn finished. Generated tokens: 256
```

### Success / Failure

```
[AUTOMATION_SUCCESS] Benchmark completed successfully.
```
or
```
[AUTOMATION_FAILURE] Failed to initialize engine: <error description>
[AUTOMATION_FAILURE] Inference run failed: <error description>
[AUTOMATION_FAILURE] No benchmark metrics captured.
[AUTOMATION_FAILURE] HF Auth required for <model>
```

### Results JSON Block

Results are emitted as a JSON block between delimiters:

```
[AUTOMATION_RESULTS_JSON]
{
  "config" : "GPU / No MTP / Greedy",
  "decode_tok_s" : 42.5,
  "init_time_s" : 3.2,
  "median_token_latency_ms" : 23.5,
  "memory_delta_mb" : 1340.2,
  "model" : "gemma4-e2b-it-q8_0.litertlm",
  "prefill_tok_s" : 156.3,
  "timestamp" : "2026-06-10T18:30:00Z",
  "ttft_s" : 0.45
}
[AUTOMATION_RESULTS_END]
```

### Parsing Results Programmatically

```bash
# Extract JSON results from stdout
xcrun simctl launch --console booted com.andrewvoirol.EdgeAILab -- -RunAllTests 2>&1 | \
  sed -n '/\[AUTOMATION_RESULTS_JSON\]/,/\[AUTOMATION_RESULTS_END\]/p' | \
  grep -v '\[AUTOMATION_RESULTS' | \
  python3 -c "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))"
```

## Matrix Benchmark Details

The `-RunMatrixBenchmark` flag runs 10 configurations:

| # | Config Label | Model | GPU | MTP | Sampler |
|---|---|---|---|---|---|
| 1 | Standard Model / GPU / No MTP / Greedy | Gemma 4 E2B | ✅ | ❌ | topK=1 |
| 2 | Standard Model / GPU / MTP / Greedy | Gemma 4 E2B | ✅ | ✅ | topK=1 |
| 3 | Standard Model / CPU / No MTP / Greedy | Gemma 4 E2B | ❌ | ❌ | topK=1 |
| 4 | Standard Model / GPU / No MTP / Sampling | Gemma 4 E2B | ✅ | ❌ | topK=64 |
| 5 | E4B Web Model / GPU / No MTP / Greedy | Gemma 4 E4B Web | ✅ | ❌ | topK=1 |
| 6 | E4B Web Model / GPU / MTP / Greedy | Gemma 4 E4B Web | ✅ | ✅ | topK=1 |
| 7 | E4B Web Model / GPU / No MTP / Sampling | Gemma 4 E4B Web | ✅ | ❌ | topK=64 |
| 8 | E4B Standard / CPU / No MTP / Greedy | Gemma 4 E4B Std | ❌ | ❌ | topK=1 |
| 9 | 12B Model / GPU / No MTP / Greedy | Gemma 4 12B | ✅ | ❌ | topK=1 |
| 10 | 12B Model / GPU / MTP / Greedy | Gemma 4 12B | ✅ | ✅ | topK=1 |

Run a single configuration:
```bash
xcrun simctl launch --console booted com.andrewvoirol.EdgeAILab -- -RunMatrixBenchmark 1
```

Between configurations, the harness:
1. Checks thermal state (waits up to 60s to cool below `.serious`)
2. Shuts down the current engine
3. Initializes with new config (GPU/CPU, MTP on/off, sampler)
4. Runs warmup + benchmark

## Crash Recovery

The benchmark pipeline includes crash-resilient state management (ported from the IO 2026 Concierge InferenceBenchmark):

### How It Works

1. **Before each config starts**: The config ID is persisted to `UserDefaults` key `benchmark_active_config`
2. **On startup**: If a stale `benchmark_active_config` key exists, the pipeline logs an `interruptedPreviousRun` event with `turnIndex: -1` and clears the key
3. **Processed tracking**: Completed configs are tracked in `benchmark_processed_configs` (UserDefaults array) so they're skipped on relaunch
4. **Warmup tagging**: Warmup turns are tagged with `turnIndex: -1` (cold probe) in JSONL output
5. **Cleanup**: All benchmark state keys are cleared after the full pipeline completes

### UserDefaults Keys

| Key | Type | Purpose |
|---|---|---|
| `benchmark_active_config` | String | Currently-running config ID (breadcrumb for crash detection) |
| `benchmark_processed_configs` | [String] | Array of completed config IDs to skip on relaunch |
| `benchmark_run_id` | String | UUID for the current benchmark session (survives restarts) |

## JSONL Streaming Output

During benchmark runs, per-turn results are streamed to `benchmark-results.jsonl` in the metrics directory. Each line is a self-contained JSON object:

### Format

```json
{"configId":"model_gpu_greedy","entry":{...},"runId":"UUID","timestamp":"ISO8601","turnIndex":0}
```

### Fields

| Field | Type | Description |
|---|---|---|
| `runId` | String (UUID) | Unique identifier for this benchmark session |
| `configId` | String | Configuration identifier (e.g. `gemma4-e2b_gpu_greedy`) |
| `turnIndex` | Int | Turn number (-1 = warmup/cold probe, 0+ = benchmark turns) |
| `timestamp` | String (ISO8601) | When this turn completed |
| `entry` | Object | Full `MetricsStore.Entry` with all benchmark metrics |

### Special Events

Non-entry events (crash recovery, warmup) use a simplified format:
```json
{"event":"interruptedPreviousRun","configId":"...","runId":"...","turnIndex":-1,"timestamp":"..."}
{"event":"warmup","configId":"...","runId":"...","turnIndex":-1,"timestamp":"..."}
```

### Stdout Protocol

All JSONL lines are also printed to stdout with a `[BENCHMARK_TURN]` prefix:
```
[BENCHMARK_TURN] {"configId":"...","runId":"...","turnIndex":0,...}
```

### Parsing JSONL

```bash
# Extract JSONL lines from device console output
grep '\[BENCHMARK_TURN\]' output.log | sed 's/^\[BENCHMARK_TURN\] //' | jq .
```

## Benchmark Metrics Captured

| Metric | Key | Unit | Description |
|---|---|---|---|
| Prefill Speed | `prefill_tok_s` | tokens/sec | Input prompt processing speed |
| Decode Speed | `decode_tok_s` | tokens/sec | Output token generation speed |
| Time to First Token | `ttft_s` | seconds | Latency before first output token |
| Init Time | `init_time_s` | seconds | Model initialization time |
| Median Token Latency | `median_token_latency_ms` | milliseconds | Median per-token decode latency |
| Memory Delta | `memory_delta_mb` | megabytes | Memory increase during inference |

## CI Integration

### ci_test_runner.sh

The project includes `automation/ci_test_runner.sh` which orchestrates the full test pyramid:

```bash
# Run full CI pipeline on macOS
./automation/ci_test_runner.sh --macOS

# Run on simulator
./automation/ci_test_runner.sh --simulator

# Skip slow tests
./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance

# Allow perf test failures without failing CI
./automation/ci_test_runner.sh --macOS --no-fail-perf
```

### run_matrix.py

For matrix benchmark orchestration:
```bash
python3 automation/run_matrix.py
```

### run_raw_benchmark.sh

For raw LiteRT-LM benchmark (no app UI):
```bash
./automation/run_raw_benchmark.sh
```

## Creating a New Automation Flow

1. Create a JSON file in `automation/flows/`:

```json
{
  "name": "My New Flow",
  "steps": [
    {
      "step": 1,
      "action": "verify_ui",
      "description": "Verify app is ready.",
      "expected_elements": ["Models", "Load Model"]
    },
    {
      "step": 2,
      "action": "tap",
      "description": "Tap the target button.",
      "target_element": "My Button"
    }
  ]
}
```

2. Launch with:
```bash
xcrun simctl launch --console booted com.andrewvoirol.EdgeAILab -- -RunFlow my_new_flow
```

The flow name in `-RunFlow` should match the filename without `.json` extension.

## Device Deployment Scripts

Two shell scripts automate build/deploy/monitor workflows for physical iOS devices:

### `automation/deploy_device.sh`

Build, install, and launch Edge AI Lab on a connected device:

```bash
# Auto-detect first connected device
./automation/deploy_device.sh

# Target a specific device
./automation/deploy_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184

# Pass launch arguments (e.g. run benchmark pipeline)
./automation/deploy_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunBenchmarkPipeline

# Run validation on device
./automation/deploy_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunValidation
```

### `automation/monitor_device.sh`

Launch the app and filter console output for benchmark/automation protocol lines:

```bash
# Monitor benchmark output
./automation/monitor_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184

# Monitor with launch arguments
./automation/monitor_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunBenchmarkPipeline
```

Filters for: `AUTOMATION_RESULTS`, `BENCHMARK_TURN`, `AUTOMATION_SUCCESS`, `AUTOMATION_FAILURE`, `VALIDATION_TEST`, `VALIDATION_COMPLETE`

## Troubleshooting

### Harness Doesn't Activate

- Verify the launch argument is passed correctly (after `--` separator)
- Check that the app was built with `DeveloperAutomationHarness.swift` included
- Look for `[AUTOMATION] Developer Automation Harness activated.` in stdout

### Download Fails

- `[AUTOMATION_FAILURE] HF Auth required` — Set `$HF_TOKEN` environment variable
- `[AUTOMATION_FAILURE] Failed to download` — Check network, verify model URL in `ModelRegistry`

### Engine Initialization Fails

- `[AUTOMATION_FAILURE] Failed to initialize engine` — Usually means model file is corrupted or incompatible
- Re-download by deleting the `.litertlm` file from Documents and running again

### No Results JSON

- Benchmark was interrupted or failed before completion
- Check for `[AUTOMATION_FAILURE]` lines above in stdout
- Ensure sufficient device memory for the selected model
