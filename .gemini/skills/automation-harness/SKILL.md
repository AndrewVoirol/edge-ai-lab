---
name: automation-harness
description: Trigger and parse the DeveloperAutomationHarness for in-app E2E testing and benchmarking via JSON automation flows. Use this skill for running benchmark flows, model setup automation, inference testing, and CI pipeline integration — especially on physical devices where XCTest hangs.
---

# Automation Harness

This skill covers the `DeveloperAutomationHarness` — an in-app automation system that runs benchmark and E2E test flows via launch arguments, outputting structured results to stdout.

## Why Use This Instead of XCTest

The automation harness exists because:
1. **On-device XCTest hangs** on iOS 26 beta (see `device-testing` skill)
2. **Benchmark flows** need the full app lifecycle (model download, GPU init, inference)
3. **CI integration** needs machine-parseable stdout output
4. **Matrix benchmarks** run multiple GPU/CPU/MTP configurations in sequence

## Launch Arguments

The harness activates based on these command-line arguments:

| Argument | Description |
|---|---|
| `-RunAllTests` | Full single-model benchmark: wipe models → download Gemma 4 E2B → GPU init → warmup → benchmark → report |
| `-RunMatrixBenchmark` | Multi-configuration matrix: runs 10 config combinations across models/GPU/CPU/MTP/sampling |
| `-RunMatrixBenchmark N` | Run only configuration N (1-indexed) from the matrix |
| `-RunFlow <name>` | Run a specific JSON automation flow from `automation/flows/` |

## Available Automation Flows

Located in `automation/flows/`:

| Flow File | Name | Purpose |
|---|---|---|
| `benchmark_flow.json` | Performance Benchmarks & Metrics Capture | Select model → warmup → benchmark prompt → capture TTFT/Decode/Memory metrics |
| `inference_flow.json` | Chat & Inference Flow | Select model → type prompt → generate → verify response with TTFT/Decode |
| `model_setup_flow.json` | Model Setup & HF Token Configuration | Verify UI → open Settings → enter HuggingFace token → close settings |
| `multimodal_flow.json` | Multimodal Inference Flow | Attach image → type prompt → generate multimodal response → verify |
| `settings_flow.json` | Settings Verification Flow | Open settings → toggle MTP → test Greedy/Default presets → set system message |

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
      "expected_elements": ["Element1", "Element2"]
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
  -workspace GemmaEdgeGallery.xcworkspace \
  -scheme GemmaEdgeGallery_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -quiet

# Launch with console output
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunAllTests
```

```bash
# Run a specific flow
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunFlow benchmark_flow
```

### On Physical Device

```bash
xcrun devicectl device process launch \
  --device "Phactivity Monitor" \
  --console \
  com.andrewvoirol.GemmaEdgeGallery \
  -- -RunAllTests
```

### Via MCP

**Simulator:**
```
Tool: xcodebuild-mcp → launch_app_sim
Arguments:
  simulator: "iPhone 16 Pro"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
  arguments: ["-RunAllTests"]
```

**Device:**
```
Tool: xcodebuild-mcp → launch_app_device
Arguments:
  device: "Phactivity Monitor"
  bundle_id: "com.andrewvoirol.GemmaEdgeGallery"
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
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunAllTests 2>&1 | \
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
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunMatrixBenchmark 1
```

Between configurations, the harness:
1. Checks thermal state (waits up to 60s to cool below `.serious`)
2. Shuts down the current engine
3. Initializes with new config (GPU/CPU, MTP on/off, sampler)
4. Runs warmup + benchmark

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
xcrun simctl launch --console booted com.andrewvoirol.GemmaEdgeGallery -- -RunFlow my_new_flow
```

The flow name in `-RunFlow` should match the filename without `.json` extension.

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
