---
name: eval-pipeline
description: >
  Debug and verify eval suite results. Covers: reading pipeline output, diagnosing
  empty responses, tool dispatch failure patterns, scorer type matching, engine
  capability flag requirements, and MLX/GGUF/LiteRT-LM-specific eval issues.
  Activate when eval scores drop unexpectedly, when adding new eval suites,
  or when debugging model response quality.
---

# Eval Pipeline Debugging

## Quick Diagnostic Checklist

When eval scores drop or prompts fail, check in this order:

1. **Engine capability flags** — Is `supportsVision`/`supportsAudio`/`supportsToolCalling` correct?
2. **Tool dispatch logs** — `grep "MLXEngine.*Tool" <log>` — are tools being invoked?
3. **Tool dispatch errors** — `grep "⚠️.*Tool" <log>` — are tools throwing?
4. **Model response text** — Read the `A: ` field in failed prompts. Empty = infrastructure. Text = scorer mismatch or model quality.
5. **Scorer type** — Does the scorer match the suite's purpose? (`.containsAny` for accuracy, `.toolCall` for tool testing)

## Engine Capability Flags

These adapter properties gate eval prompt routing. Missing or incorrect flags cause **silent failures** (empty responses scored as 0%):

| Flag | Property | Effect on Eval |
|---|---|---|
| `supportsVision` | `var supportsVision: Bool` | Gates image prompts — missing = all image prompts get empty response |
| `supportsAudio` | `var supportsAudio: Bool` | Gates audio prompts — missing = all audio prompts skipped |
| `supportsToolCalling` | `var supportsToolCalling: Bool` | Gates tool-dependent suites — missing = tools not registered |

**Rule:** A missing capability flag causes SILENT failures. The eval runner doesn't log "skipped because supportsVision=false" — it just sends the prompt without the image, and the model responds with generic text that fails scoring.

**When adding a new engine adapter:** Always verify all three capability flags are implemented and return correct values. A missing `supportsVision = true` caused a +88pp regression that looked like a model quality issue.

## Reading Eval Pipeline Output

Key diagnostic lines in eval pipeline output:

| Line Pattern | Meaning |
|---|---|
| `Engine loaded: runtime=X, supportsToolCalling=Y, tools=Z` | Engine capabilities for this suite. If `tools=0` on a tool-dependent suite, tools aren't registered |
| `Score: N/M (P%)` | Suite result |
| `❌ Failed prompts (N):` | Followed by individual failures with truncated model responses |
| `A: ` (empty) | Model returned no text — usually a tool dispatch failure or silent crash |
| `A: <text>` | Model responded but the scorer didn't match. Read the text to diagnose |
| `⚠️ Passed K/5 runs (majority vote)` | Majority-vote scoring (5 runs). K<3 = fail |

## Tool Dispatch Flow

```
Model generates tool call JSON
    → ChatSession parses via ToolCallFormat (.gemma4)
    → session.toolDispatch closure invoked
    → ToolToAppToolAdapter.execute()
        → Coerce string→number types
        → Inject defaults for missing optional params (commit af08752)
        → JSONDecoder.decode(T.self, from: jsonData)
        → tool.run()
    → Result string returned to model
    → Model generates final answer
```

**Common failure point:** Before commit af08752, `JSONDecoder.decode` threw `DecodingError.keyNotFound` for any optional parameter the model omitted (e.g., `timezone` in `get_current_datetime`). The fix injects type-appropriate defaults for missing non-required params before decoding.

## Tool Dispatch Diagnostics

MLX engine logs tool dispatch with emoji prefixes:
```
[MLXEngine] 🔧 Tool dispatch: <name> with args: [<args>]
[MLXEngine] ✅ Tool <name> returned: {<result>}
[MLXEngine] ⚠️ Tool <name> failed, returning error to model: <error>
```

**If tool calls show `⚠️`:** The error is returned as a string to the model (not thrown). The model may or may not use it to formulate a response.

**If no tool dispatch logs appear for a suite that needs tools:** Check `EvalRunner` to verify the suite enables tool calling.

## Empty Response Diagnosis

| Empty `A: ` on... | Likely Cause | Fix |
|---|---|---|
| ALL prompts in a suite | Engine not loaded or crashed | Check for `[AUTOMATION_FAILURE]` |
| ALL vision prompts | `supportsVision` missing | Add `var supportsVision: Bool { true }` to adapter |
| ALL audio prompts | SDK audio processor limitation | Check `[MLXEngine] 📎 Multimodal input:` logs |
| Tool-dependent prompts only | Tool dispatch error | Check `[MLXEngine] 🔧 Tool dispatch:` logs |
| Conversion prompts (F→C, km→mi) | Unit converter doesn't recognize aliases | Expand UnitConverterTool alias dictionary |
| DateTime prompts | Optional param not defaulted | Verify ToolToAppToolAdapter default injection |
| After model_type change | Architecture mismatch | REVERT immediately — weight structures incompatible |

## MLX-Specific Eval Issues

### Audio: SDK Limitation

At pinned commit bc95ffb66213, MLX audio inference does not work:
- `Gemma4.sanitize()` strips audio weights
- No mel spectrogram extraction in processor
- Audio prompts return: "Please provide the audio"
- Only 2/25 Multimodal prompts affected (the audio ones)

### Tool Calling Quality (4-bit)

4-bit quantized models have reduced tool-calling coherence:
- Model generates tool call correctly
- Tool executes and returns valid result  
- Model stops generating instead of incorporating the result
- This is a quantization quality issue, not infrastructure

### model_type Architecture Mapping

NEVER modify `config.json` model_type. See mlx-engine skill for the full mapping table. Key fact: `gemma4` and `gemma4_unified` use incompatible vision pipelines — switching breaks vision (92%→4%).

## Running Targeted Evaluations

```bash
# Full pipeline (all engines, all suites) — ~110 min
"/path/to/Edge AI Lab.app/Contents/MacOS/Edge AI Lab" -RunEvalPipeline 2>&1

# Monitor progress during run
grep -E "Score:|Running suite:|─── Model" <log>

# Check for tool errors  
grep "⚠️.*Tool\|❌.*Tool" <log>

# Get final scoreboard
grep -E "Score:|─── Model" <log>

# Check tool dispatch success/failure
grep "MLXEngine.*Tool" <log>
```

## Pipeline Run Time Estimates

| Scope | Approximate Duration |
|---|---|
| Full 3×9 pipeline (GGUF + LiteRT + MLX) | ~110 min |
| Single engine × 9 suites | ~35-40 min |
| GGUF only | ~25 min (fastest engine) |
| MLX only | ~40 min (slowest, 4-bit decode) |
| LiteRT-LM only | ~35 min |

When debugging a single engine, previous run data for other engines is typically stable across runs. Focus re-runs on the changed engine.

## Eval History

Results are persisted to `metrics/eval_history.json` in a `{"_meta": ..., "runs": [...]}` structure. Each run entry contains per-suite scores, timestamps, and engine metadata.
