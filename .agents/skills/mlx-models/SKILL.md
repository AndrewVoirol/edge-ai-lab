---
name: mlx-models
description: >
  HuggingFace MLX model selection, quantization caveats, file structure, memory
  estimation, and recommended models for Edge AI Lab. Activate when selecting MLX
  models, estimating memory requirements, debugging model quality issues, or
  working with mlx-community HuggingFace repos.
---

# MLX Models Skill

## Model Selection — Critical: PLE Quantization

### The #1 Gotcha for Gemma 4 on MLX

Gemma 4 uses **Per-Layer Embeddings (PLE)**. Standard uniform 4-bit quantization breaks these layers, producing **garbage output**.

**Safe choices:**
- ✅ **OptiQ variants** (`-OptiQ-4bit`) — sensitivity-aware mixed-precision, PLE layers kept at bf16/8-bit
- ✅ **QAT variants** — Quantization-Aware Trained by Google directly
- ✅ **8-bit and bf16** — higher precision avoids the issue entirely

**Avoid:**
- ⚠️ **Standard uniform `-4bit`** — may produce broken output unless the model card explicitly confirms PLE-safe quantization

### Recommended Gemma 4 Variants

| Model ID | Params | Size | Quality | Use Case |
|----------|--------|------|---------|----------|
| `mlx-community/gemma-4-e2b-it-OptiQ-4bit` | E2B (~2B) | ~2.6 GB | ✅ PLE-safe | **Primary test model** |
| `mlx-community/gemma-4-e2b-it-4bit` | E2B (~2B) | ~1.5–2.6 GB | ⚠️ PLE risk | Use only if OptiQ unavailable |
| `mlx-community/gemma-4-e4b-it-OptiQ-4bit` | E4B (~4B) | ~4 GB | ✅ PLE-safe | Better quality, still edge-sized |
| `mlx-community/gemma-4-12b-it-4bit` | 12B | ~8 GB | Multimodal | Text + image + audio |
| `mlx-community/gemma-4-26b-a4b-it-4bit` | 26B MoE (4B active) | ~18 GB | High quality | Needs 24+ GB Mac |

### Fallback Test Models (Non-Gemma)

If Gemma 4 has issues, these are reliable alternatives:

| Model | Size | Notes |
|-------|------|-------|
| `mlx-community/Phi-4-mini-4bit` | ~2.5 GB | Great perf-to-size, Microsoft |
| `mlx-community/Llama-3.2-3B-Instruct-4bit` | ~2.5 GB | Reliable all-rounder |
| `mlx-community/Qwen3.5-9B-4bit` | ~6 GB | Strong coding/agentic |

## Model File Structure

A typical MLX model repo on HuggingFace contains:

```
├── config.json                          # Architecture config
├── model.safetensors                    # Weights (single file for small models)
│   OR
├── model-00001-of-00003.safetensors     # Sharded weights (larger models)
├── model-00002-of-00003.safetensors
├── model-00003-of-00003.safetensors
├── model.safetensors.index.json         # Shard index
├── tokenizer.json                       # Tokenizer vocabulary
├── tokenizer_config.json                # Tokenizer settings
├── tokenizer.model                      # SentencePiece (if applicable)
├── special_tokens_map.json              # Special token mapping
└── README.md                            # Model card
```

**File counts by model size:**
- E2B/E4B (small): typically 1 safetensors file
- 12B (medium): 2-3 sharded safetensors files
- 26B+ (large): 4-8+ sharded safetensors files

All weights use `.safetensors` format (secure, memory-mappable).

## Memory Estimation

### Formula

```
Estimated RAM = (model_size_on_disk × 1.2) + KV_cache_overhead
```

The 1.2× multiplier accounts for:
- Dequantization buffers (4-bit → float16 for compute)
- Intermediate activation tensors
- Metal command buffer overhead

KV cache overhead depends on context length and model architecture.

### Quick Reference Table

| Model | 4-bit Download | Estimated RAM Needed | Minimum Mac RAM |
|-------|---------------|---------------------|-----------------|
| Gemma 4 E2B | ~2.6 GB | ~3-4 GB | 8 GB |
| Gemma 4 E4B | ~4 GB | ~5-6 GB | 8 GB |
| Gemma 4 12B | ~8 GB | ~10 GB | 16 GB |
| Gemma 4 26B MoE | ~18 GB | ~22 GB | 24-36 GB |
| Gemma 4 31B | ~20 GB | ~24 GB | 24-36 GB |

### iPhone Memory Limits

| Device | Total RAM | Available for App | Max Feasible Model |
|--------|----------|-------------------|-------------------|
| iPhone 15 Pro / 16 Pro | 8 GB | ~4-6 GB (with entitlement) | E2B 4-bit, maybe E4B |
| iPhone 16 Pro Max | 8 GB | ~4-6 GB (with entitlement) | E2B 4-bit, maybe E4B |

**ALWAYS** add the `Increased Memory Limit` entitlement for iOS targets running MLX models.

## Naming Conventions

### HuggingFace Model IDs

Pattern: `mlx-community/{model}-{size}-{variant}-{quant}`

- `it` = instruction-tuned
- `OptiQ` = sensitivity-aware mixed-precision quantization
- `4bit` / `8bit` / `bf16` = quantization level
- `E2B` / `E4B` = effective parameter count (edge models)

### Runtime Type Mapping

| HuggingFace Org | Library Name | RuntimeType | File Extension |
|-----------------|-------------|-------------|---------------|
| `litert-community` | `litert` | `.litertlm` | `.litertlm` |
| `mlx-community` | `mlx` | `.mlx` | `.safetensors` |

## Model Quality Debugging

If an MLX model produces garbage, incoherent, or repetitive output:

1. **Check quantization**: Is it a standard uniform 4-bit Gemma 4 model? → PLE issue. Switch to OptiQ.
2. **Check temperature**: Temperature 0.0 can cause repetitive output. Try 0.6-0.8.
3. **Check `repetitionPenalty`**: Set to 1.05-1.2 to reduce repetition.
4. **Check context length**: Very long contexts can degrade quality. Consider `maxKVSize` parameter.
5. **Check model loading**: Verify all safetensors files downloaded completely. Truncated files produce corrupted weights.
6. **Compare with known-good model**: Try Phi-4-mini or Llama 3.2 to verify the engine works correctly before blaming the model.

## Vision/VLM Models

Gemma 4 is natively multimodal — E2B, E4B, and 12B all support image input.

For VLMs, use `MLXVLM` package:
- `VLMModelFactory.shared.loadContainer(...)` instead of `LLMModelFactory`
- `VLMRegistry` instead of `LLMRegistry`

Other supported VLMs: Qwen2-VL, Qwen3-VL, LLaVA, Pixtral, PaliGemma, Phi-3/4 Vision.

**Phase 4 note**: VLM support comes in Phase 4. Phase 1-2 are text-only LLM.
