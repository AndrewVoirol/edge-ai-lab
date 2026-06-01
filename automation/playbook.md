# GemmaEdgeGallery — UI Automation Playbook (Physical Device)

This playbook describes how to run automated flows and extract performance metrics from the `GemmaEdgeGallery_iOS` app running on the connected physical iPhone.

---

## Workspace Setup

Ensure your session defaults are configured to target the physical device:
```json
{
  "workspacePath": "/Users/andrewvoirol/Antigravity/Projects/gemma-edgegallery/GemmaEdgeGallery.xcworkspace",
  "scheme": "GemmaEdgeGallery_iOS",
  "deviceId": "3B50314A-0702-5188-A321-BCD5CA5F8184"
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
