#!/usr/bin/env bash
# benchmark_compare.sh — Compares benchmark results against baselines for regression detection.
#
# Usage:
#   ./automation/benchmark_compare.sh \
#     --results benchmark_results.json \
#     --baselines metrics/baselines.json \
#     --threshold 10 \
#     --output regression_report.json
#
# Exit codes:
#   0 — No regression (stable or improved)
#   1 — Regression detected (metrics degraded beyond threshold)
#   2 — Error (missing files, parse failure)

set -euo pipefail

# ──────────────────────────────────────────────────────────
# Arguments
# ──────────────────────────────────────────────────────────
RESULTS_FILE=""
BASELINES_FILE=""
THRESHOLD=10
OUTPUT_FILE="regression_report.json"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --results)    RESULTS_FILE="$2"; shift 2 ;;
        --baselines)  BASELINES_FILE="$2"; shift 2 ;;
        --threshold)  THRESHOLD="$2"; shift 2 ;;
        --output)     OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)
            echo "Usage: $0 --results FILE --baselines FILE [--threshold PCT] [--output FILE]"
            exit 0 ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 2 ;;
    esac
done

if [[ -z "$RESULTS_FILE" || -z "$BASELINES_FILE" ]]; then
    echo "❌ --results and --baselines are required" >&2
    exit 2
fi

if [[ ! -f "$RESULTS_FILE" ]]; then
    echo "❌ Results file not found: $RESULTS_FILE" >&2
    exit 2
fi

if [[ ! -f "$BASELINES_FILE" ]]; then
    echo "⚠️  Baselines file not found: $BASELINES_FILE"
    echo "   This is the first run — no regression check possible."
    cat > "$OUTPUT_FILE" << EOF
{
  "status": "first_run",
  "message": "No baselines found. This run will become the baseline.",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    exit 0
fi

# ──────────────────────────────────────────────────────────
# Compare using Python (available on all macOS runners)
# ──────────────────────────────────────────────────────────
export RESULTS_FILE BASELINES_FILE THRESHOLD OUTPUT_FILE
python3 << 'PYTHON_EOF'
import json
import sys
import os
from datetime import datetime, timezone

# Load inputs
results_file = os.environ.get("RESULTS_FILE", "benchmark_results.json")
baselines_file = os.environ.get("BASELINES_FILE", "metrics/baselines.json")
threshold = float(os.environ.get("THRESHOLD", "10"))
output_file = os.environ.get("OUTPUT_FILE", "regression_report.json")

# Load results — supports both single-JSON and JSONL (JSON Lines) formats.
# JSONL files contain one JSON object per line. Lines with an "event" key are
# warmup/progress entries; the last non-event line is the actual benchmark data.
# JSONL uses "configId" (e.g. "modelFile_gpu_greedy") instead of separate
# "model" / "backend_used" keys.
with open(results_file) as f:
    raw = f.read().strip()

results = None
try:
    # Try single-JSON first (old format)
    parsed = json.loads(raw)
    if isinstance(parsed, dict):
        results = parsed
except json.JSONDecodeError:
    pass

if results is None:
    # JSONL format: read line by line, skip warmup (lines with "event" key),
    # keep the last data line as the benchmark result.
    last_data = None
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
            if isinstance(obj, dict) and "event" not in obj:
                last_data = obj
        except json.JSONDecodeError:
            continue
    if last_data is None:
        print(f"❌ Could not parse any data entries from JSONL: {results_file}", file=sys.stderr)
        sys.exit(2)
    results = last_data

with open(baselines_file) as f:
    baselines_data = json.load(f)

baselines = baselines_data.get("baselines", [])
rules = baselines_data.get("regression_rules", {})

# Match the result to a baseline by model filename and backend.
# Old format has "model" and "backend_used" keys directly.
# JSONL format has "configId" (e.g. "gemma-4-E2B-it.litertlm_gpu_greedy")
# where the model is everything before the backend token and the backend
# is the token after the model filename (gpu/cpu).
result_model = results.get("model", "")
result_backend = results.get("backend_used", "")

if not result_model and "configId" in results:
    # Extract model and backend from configId.
    # configId format: "<modelFilename>_<backend>_<sampler>"
    # e.g. "gemma-4-E2B-it.litertlm_gpu_greedy"
    # Split from right since model filenames could contain underscores;
    # the last two tokens are always sampler and backend.
    config_id = results["configId"]
    parts = config_id.rsplit("_", 2)
    if len(parts) == 3:
        result_model = parts[0]    # model filename
        result_backend = parts[1]  # gpu, cpu, etc.
    elif len(parts) == 2:
        result_model = parts[0]
        result_backend = parts[1]
    else:
        result_model = config_id
        result_backend = ""

matched_baseline = None
for bl in baselines:
    if bl["model"] == result_model and bl["backend"] == result_backend:
        matched_baseline = bl
        break

# If no exact match, try matching just by model
if matched_baseline is None:
    for bl in baselines:
        if bl["model"] == result_model:
            matched_baseline = bl
            break

report = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "result_model": result_model,
    "result_backend": result_backend,
    "threshold_pct": threshold,
    "matched_baseline": matched_baseline["id"] if matched_baseline else None,
    "comparisons": [],
    "status": "stable",
    "regressions": [],
    "improvements": [],
}

if matched_baseline is None:
    report["status"] = "no_baseline"
    report["message"] = f"No baseline found for model='{result_model}' backend='{result_backend}'"
    print(f"⚠️  No baseline found for {result_model} / {result_backend}")
    print(f"   Available baselines: {[b['id'] for b in baselines]}")
else:
    baseline_metrics = matched_baseline["metrics"]
    print(f"📊 Comparing against baseline: {matched_baseline['id']}")
    print(f"   Source: {matched_baseline.get('source', 'unknown')}")
    print(f"   Threshold: {threshold}%")
    print()

    has_regression = False
    has_improvement = False

    # Key mapping: baselines/rules use sdk_-prefixed names, but JSONL data from
    # the device uses shorter names. Map baseline keys → JSONL keys for lookup.
    KEY_MAP = {
        "sdk_decode_tok_s": "decode_tok_s",
        "sdk_prefill_tok_s": "prefill_tok_s",
        "sdk_ttft_s": "ttft_s",
        "wall_pure_decode_tok_s": "decode_tok_s",  # same metric, different name
        "decode_median_latency_ms": "median_token_latency_ms",
        "decode_p95_latency_ms": "",  # JSONL doesn't have p95; skip comparison
        "model_load_time_s": "init_time_s",
    }

    for metric_key, rule in rules.items():
        baseline_val = baseline_metrics.get(metric_key)
        # Try the metric key directly, then fall back to the mapped JSONL key
        result_val = results.get(metric_key) or results.get(KEY_MAP.get(metric_key, ""))

        if baseline_val is None or result_val is None:
            continue

        if baseline_val == 0:
            pct_change = 0.0
        else:
            pct_change = ((result_val - baseline_val) / abs(baseline_val)) * 100.0

        direction = rule.get("direction", "higher_is_better")
        metric_threshold = rule.get("threshold_pct", threshold)
        severity = rule.get("severity", "info")

        # Determine if this is a regression
        is_regression = False
        is_improvement = False
        if direction == "higher_is_better":
            # Lower is worse
            if pct_change < -metric_threshold:
                is_regression = True
            elif pct_change > metric_threshold:
                is_improvement = True
        else:  # lower_is_better
            # Higher is worse
            if pct_change > metric_threshold:
                is_regression = True
            elif pct_change < -metric_threshold:
                is_improvement = True

        status_icon = "✅"
        if is_regression:
            status_icon = "❌" if severity == "critical" else "⚠️"
            has_regression = True
            report["regressions"].append({
                "metric": metric_key,
                "baseline": baseline_val,
                "current": result_val,
                "change_pct": round(pct_change, 1),
                "threshold_pct": metric_threshold,
                "severity": severity,
                "description": rule.get("description", ""),
            })
        elif is_improvement:
            status_icon = "🎉"
            has_improvement = True
            report["improvements"].append({
                "metric": metric_key,
                "baseline": baseline_val,
                "current": result_val,
                "change_pct": round(pct_change, 1),
            })

        comparison = {
            "metric": metric_key,
            "baseline": baseline_val,
            "current": result_val,
            "change_pct": round(pct_change, 1),
            "threshold_pct": metric_threshold,
            "direction": direction,
            "status": "regression" if is_regression else ("improved" if is_improvement else "stable"),
        }
        report["comparisons"].append(comparison)

        # Print human-readable line
        unit = "tok/s" if "tok_s" in metric_key else ("ms" if "ms" in metric_key else "s")
        change_str = f"{pct_change:+.1f}%"
        print(f"  {status_icon} {rule.get('description', metric_key)}: {result_val:.1f}{unit} "
              f"(baseline: {baseline_val:.1f}{unit}, {change_str})")

    # Determine overall status
    critical_regressions = [r for r in report["regressions"] if r["severity"] == "critical"]
    if critical_regressions:
        report["status"] = "regression"
    elif has_improvement and not has_regression:
        report["status"] = "improved"
    elif has_regression:
        report["status"] = "warning"  # Non-critical regressions only
    else:
        report["status"] = "stable"

    print()
    print(f"{'='*60}")
    if report["status"] == "regression":
        print(f"❌ REGRESSION — {len(critical_regressions)} critical metric(s) degraded")
    elif report["status"] == "warning":
        print(f"⚠️  WARNING — non-critical regressions detected")
    elif report["status"] == "improved":
        print(f"🎉 IMPROVED — {len(report['improvements'])} metric(s) improved")
    else:
        print(f"✅ STABLE — all metrics within acceptable range")
    print(f"{'='*60}")

# Write report
with open(output_file, "w") as f:
    json.dump(report, f, indent=2)

print(f"\n📄 Report written to: {output_file}")

# Exit with appropriate code
if report["status"] == "regression":
    sys.exit(1)
else:
    sys.exit(0)
PYTHON_EOF
