#!/usr/bin/env python3
import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime

DEFAULT_DEVICE_ID = "3B50314A-0702-5188-A321-BCD5CA5F8184"
BUNDLE_ID = "com.andrewvoirol.GemmaEdgeGallery"
REPORT_DIR = "automation/results"
REPORT_FILE = os.path.join(REPORT_DIR, "benchmark_report.md")

CONFIG_MAP = {
    1: "Standard Model / GPU / No MTP / Greedy",
    2: "Standard Model / Greedy / MTP / Greedy",
    3: "Standard Model / CPU / No MTP / Greedy",
    4: "Standard Model / GPU / No MTP / Sampling (topK=64)",
    5: "E4B Web Model / GPU / No MTP / Greedy",
    6: "E4B Web Model / GPU / MTP / Greedy",
    7: "E4B Web Model / GPU / No MTP / Sampling (topK=64)",
    8: "E4B Standard Model / CPU / No MTP / Greedy"
}

def check_device_connected(device_id):
    print(f"Checking connectivity for device: {device_id}...")
    try:
        res = subprocess.run(
            ["xcrun", "devicectl", "list", "devices"],
            capture_output=True,
            text=True,
            check=True
        )
        if device_id in res.stdout:
            print("Device is connected.")
            return True
        else:
            print(f"Error: Device {device_id} not found in connected devices.")
            return False
    except Exception as e:
        print(f"Warning: Failed to verify device list via devicectl: {e}")
        return True # Fallback to trying launch anyway

def run_config(device_id, config_id):
    config_name = CONFIG_MAP.get(config_id, f"Unknown Config {config_id}")
    print("\n" + "="*60)
    print(f"⚙️  RUNNING CONFIG {config_id}: {config_name}")
    print("="*60)

    cmd = [
        "xcrun", "devicectl", "device", "process", "launch",
        "--device", device_id,
        "--console", BUNDLE_ID,
        "--", "-RunMatrixBenchmark", str(config_id)
    ]

    print(f"Executing: {' '.join(cmd)}")
    
    # We read stdout line-by-line to parse results in real-time
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)

    json_capture = []
    in_json_block = False
    
    for line in iter(process.stdout.readline, ''):
        print(line, end='', flush=True) # Echo live log line to console
        
        if "[AUTOMATION_RESULTS_JSON]" in line:
            in_json_block = True
            continue
        elif "[AUTOMATION_RESULTS_END]" in line:
            in_json_block = False
            continue
        
        if in_json_block:
            json_capture.append(line)

    process.wait()
    
    if process.returncode != 0:
        print(f"Warning: Process launch returned non-zero code {process.returncode}")

    json_str = "".join(json_capture).strip()
    if json_str:
        try:
            return json.loads(json_str)
        except Exception as e:
            print(f"Error parsing JSON results: {e}")
            return None
    else:
        print("Error: No benchmark results block detected in output.")
        return None

def format_markdown_table(results):
    headers = [
        "Config #", "Configuration Description", "Decode Speed (tok/s)",
        "Prefill Speed (tok/s)", "TTFT (s)", "Init Time (s)",
        "Median Latency (ms)", "Memory Delta (MB)"
    ]
    
    rows = []
    for r in results:
        cfg_num = r.get("config_id", "?")
        desc = r.get("config", "?")
        # Extract name without long prefixes if needed, but the printed description is fine
        rows.append([
            f"**{cfg_num}**",
            desc,
            f"{r.get('decode_tok_s', 0.0):.2f}",
            f"{r.get('prefill_tok_s', 0.0):.2f}",
            f"{r.get('ttft_s', 0.0):.3f}",
            f"{r.get('init_time_s', 0.0):.2f}",
            f"{r.get('median_token_latency_ms', 0.0):.2f}",
            f"{r.get('memory_delta_mb', 0.0):.2f}"
        ])
        
    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for row in rows:
        lines.append("| " + " | ".join(row) + " |")
        
    return "\n".join(lines)

def main():
    parser = argparse.ArgumentParser(description="Automate process-isolated matrix benchmarks on physical iPhone.")
    parser.add_argument("--device", default=DEFAULT_DEVICE_ID, help="Target physical device UDID")
    parser.add_argument("--config", default="1,2,3,4,5,6,7,8", help="Comma-separated matrix config IDs to run")
    parser.add_argument("--cpu-only", action="store_true", help="Shortcut to run configuration 3 (CPU) only")
    
    args = parser.parse_args()
    
    if args.cpu_only:
        configs_to_run = [3]
    else:
        try:
            configs_to_run = [int(x.strip()) for x in args.config.split(",") if x.strip()]
        except ValueError:
            print("Error: Invalid --config IDs. Must be comma-separated integers (e.g. 1,2,3)")
            sys.exit(1)
            
    if not check_device_connected(args.device):
        sys.exit(1)
        
    results = []
    
    for cfg in configs_to_run:
        result_array = run_config(args.device, cfg)
        if result_array and isinstance(result_array, list) and len(result_array) > 0:
            res_dict = result_array[0]
            res_dict["config_id"] = cfg
            results.append(res_dict)
        # 10 seconds cooldown between runs as requested by workflow
        if cfg != configs_to_run[-1]:
            print("\n[AUTOMATION] Cooling down SoC for 10 seconds before next configuration...")
            time.sleep(10)
            
    if not results:
        print("\nNo benchmarks successfully executed.")
        sys.exit(1)
        
    table_md = format_markdown_table(results)
    
    print("\n" + "="*60)
    print("🏆 CONSOLIDATED BENCHMARK MATRIX RESULTS")
    print("="*60 + "\n")
    print(table_md)
    print("\n" + "="*60 + "\n")
    
    # Save/append report
    os.makedirs(REPORT_DIR, exist_ok=True)
    
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    report_header = f"### Benchmark Run: {now_str}\nDevice ID: `{args.device}`\n\n"
    
    file_exists = os.path.exists(REPORT_FILE)
    with open(REPORT_FILE, "a") as f:
        if not file_exists:
            f.write("# GemmaEdgeGallery On-Device Benchmark Reports\n\n")
        f.write(report_header)
        f.write(table_md)
        f.write("\n\n---\n\n")
        
    print(f"Report successfully appended to: {REPORT_FILE}")

if __name__ == "__main__":
    main()
