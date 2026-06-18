# EdgeAILab — UI Automation Playbook (Physical Device)

This playbook describes how to run automated flows and extract performance metrics from the `EdgeAILab_iOS` app running on the connected physical iPhone.

---

## Workspace Setup

Ensure your session defaults are configured to target the physical device:
```json
{
  "workspacePath": "/path/to/your/EdgeAILab.xcworkspace",
  "scheme": "EdgeAILab_iOS",
  "deviceId": "YOUR_DEVICE_UUID"
}
```

---

## Step-by-Step Execution Lifecycle

For each declarative flow:
1. **Clean/Build/Deploy**: Run `clean`, `build_device`, and `install_app_device` to ensure the latest binary is running.
2. **Launch**: Run `launch_app_device`.
3. **Wait for UI**: Call `snapshot_ui` or `screenshot` to verify that the app is open and initial elements (e.g. "Models" header, "Load Model" button) are visible.
4. **Locate and Interact**:
   - Call `snapshot_ui` to dump the hierarchy.
   - Look for the target element's label/text and extract its coordinates (center x, center y).
   - Call `tap` with the coordinates, or search query.
   - For text fields, call `type_text` with the string.
5. **Verify State**: Take a new `snapshot_ui` or `screenshot` after each interaction to verify state progression.

---

## Extracting Benchmarking Metrics

Once a benchmark text generation has completed:
1. Locate the chevron button in the benchmark bar (which appears at the bottom once inference finishes).
2. Tap the chevron to expand the detailed view.
3. Call `snapshot_ui` to retrieve the text values:
   - **TTFT (Time To First Token)**: Look for the value next to `TTFT`.
   - **Decode Speed**: Look for the value next to `Decode`.
   - **Prefill Speed**: Look for the value next to `Prefill`.
   - **Memory Delta**: Look for the value next to `Δ Memory`.
4. Log these values to the corresponding results run.

---

## In-App Pipelines

The automation harness includes two integrated pipelines that can be run via launch arguments:

### Benchmark Pipeline (`-RunBenchmarkPipeline`)

**Purpose**: Run benchmarks and compare against baselines for regression detection.

```bash
# Real mode (requires models on disk)
.../Edge\ AI\ Lab -RunBenchmarkPipeline

# Dry-run (validates plumbing only — no model needed)
.../Edge\ AI\ Lab -RunBenchmarkPipeline -DryRun
```

**What it does**:
1. Loads and validates `metrics/baselines.json`
2. Discovers local `.litertlm` model files
3. Runs a single-model benchmark (GPU + Greedy config)
4. Compares results against baselines using `BenchmarkRegressionChecker`
5. Reports critical/warning/info regressions via `[AUTOMATION_BENCHMARK_REGRESSION]` stdout

### Eval Pipeline (`-RunEvalPipeline`)

**Purpose**: Run built-in eval suites against models and report scored results (informational).

```bash
# Real mode (requires models on disk)
.../Edge\ AI\ Lab -RunEvalPipeline

# Dry-run (validates suite loading, store creation — no model needed)
.../Edge\ AI\ Lab -RunEvalPipeline -DryRun
```

**What it does**:
1. Loads all `BuiltInEvalSuites.allBuiltIn` suites
2. Validates suite structure (non-empty names, valid prompts)
3. Discovers local models
4. Runs each suite against the model, scoring pass/fail per prompt
5. Reports results via `[AUTOMATION_EVAL_RESULTS_JSON]` stdout

### Dry-Run Mode (`-DryRun`)

The `-DryRun` modifier can be combined with any `-Run*` argument to:
- Skip real UI assertions (flow step verification)
- Skip model initialization and inference
- Validate that all pipeline plumbing works (JSON parsing, flow discovery, suite loading)

This is used in CI on runners that don't have GPUs or pre-staged models.

---

## Device Deployment & Monitoring

Two shell scripts in `automation/` automate the build → install → launch → monitor lifecycle for physical iOS devices.

### Quick Start

```bash
# Build, install, and launch with benchmark pipeline
./automation/deploy_device.sh <DEVICE_ID> -RunBenchmarkPipeline

# Monitor output (filters for benchmark/automation protocol lines)
./automation/monitor_device.sh <DEVICE_ID> -RunBenchmarkPipeline
```

### `deploy_device.sh`

Full build-install-launch cycle:

| Step | What it does |
|---|---|
| 1. Device detection | Accepts explicit `DEVICE_ID` or auto-detects first connected device |
| 2. Build | `xcodebuild build` targeting `EdgeAILab_iOS` for the device |
| 3. Install | `xcrun devicectl device install app` |
| 4. Launch | `xcrun devicectl device process launch --console` with pass-through launch args |

```bash
# Auto-detect device
./automation/deploy_device.sh

# Specific device with launch args
./automation/deploy_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunBenchmarkPipeline -DryRun

# Run validation checks
./automation/deploy_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunValidation
```

### `monitor_device.sh`

Launches the app and filters console output for key protocol lines:

- `AUTOMATION_RESULTS` — JSON result blocks
- `BENCHMARK_TURN` — Per-turn JSONL streaming output
- `AUTOMATION_SUCCESS` / `AUTOMATION_FAILURE` — Pass/fail signals
- `VALIDATION_TEST` / `VALIDATION_COMPLETE` — Validation check results

```bash
./automation/monitor_device.sh 3B50314A-0702-5188-A321-BCD5CA5F8184 -RunBenchmarkPipeline
```

### Finding Your Device ID

```bash
xcrun devicectl list devices
```

---

## JSONL Benchmark Streaming

When running `-RunBenchmarkPipeline`, per-turn results are streamed in two ways:

1. **JSONL file**: `metrics/benchmark-results.jsonl` (one JSON object per line)
2. **stdout**: Lines prefixed with `[BENCHMARK_TURN]`

Each line includes `runId`, `configId`, `turnIndex`, `timestamp`, and the full metrics entry. Warmup turns use `turnIndex: -1`. Crash-recovery events use `event: "interruptedPreviousRun"`.

```bash
# Parse JSONL from captured output
grep '\[BENCHMARK_TURN\]' output.log | sed 's/^\[BENCHMARK_TURN\] //' | jq .
```

---

## CI Integration

### Automation Flows Job (`ci.yml → automation-flows`)

Runs on every push/PR. Executes `AutomationHarnessXCTests`:
- `testAllFlowsDiscoverable` — `-ListFlows`
- `testE2ERegressionFlowDryRun` — `-RunFlow e2e_regression_flow -DryRun`
- `testBenchmarkFlowDryRun` — `-RunFlow benchmark_flow -DryRun`
- `testDryRunModifierAccepted` — `-RunAllFlows -DryRun`

### Benchmark Pipeline Validation (`benchmark.yml → dry-run-validation`)

Runs on PRs that touch `Sources/Benchmarking/**`, `automation/**`, or `metrics/baselines.json`:
- Validates `baselines.json` schema
- Validates all flow JSONs parse correctly
- Runs `BenchmarkPipelineTests` and `EvalPipelineTests`

### Self-Hosted Benchmark (`benchmark.yml → self-hosted-benchmark`)

Runs on `[self-hosted, apple-silicon]` runners on release/schedule/dispatch:
- Discovers pre-staged models in `~/models/`
- Runs full RawBenchmark CLI
- Compares against baselines
- Uploads results as artifacts

---

## Self-Hosted Runner Reference

For setting up a local Mac as a GitHub Actions self-hosted runner, see [../SELF_HOSTED_RUNNER.md](../SELF_HOSTED_RUNNER.md).

Quick verification:

```bash
# Verify runner can execute tests
./automation/ci_test_runner.sh --macOS --skip-integration --skip-performance

# Verify model discovery works
ls ~/models/*.litertlm
```
