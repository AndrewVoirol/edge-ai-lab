# GemmaEdgeGallery On-Device Benchmark Reports

### Benchmark Run: 2026-06-01 18:33:08
Device ID: `YOUR_DEVICE_UUID`

| Config # | Configuration Description | Decode Speed (tok/s) | Prefill Speed (tok/s) | TTFT (s) | Init Time (s) | Median Latency (ms) | Memory Delta (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **1** | Standard Model / GPU / No MTP / Greedy | 14.50 | 32.21 | 0.379 | 2.06 | 27.21 | -213.22 |

---

### Benchmark Run: 2026-06-01 19:11:15
Device ID: `YOUR_DEVICE_UUID`

| Config # | Configuration Description | Decode Speed (tok/s) | Prefill Speed (tok/s) | TTFT (s) | Init Time (s) | Median Latency (ms) | Memory Delta (MB) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **5** | E4B Web Model / GPU / No MTP / Greedy | 16.78 | 3.63 | 2.817 | 3.63 | 58.50 | 6.08 |
| **6** | E4B Web Model / GPU / MTP / Greedy | 17.42 | 3.79 | 2.694 | 3.52 | 54.97 | -11.83 |
| **7** | E4B Web Model / GPU / No MTP / Sampling (topK=64) | 17.20 | 3.80 | 2.690 | 3.52 | 57.42 | -9.23 |
| **8** | E4B Standard Model / CPU / No MTP / Greedy | 4.47 | 5.59 | 2.014 | 22.45 | 90.66 | -129.19 |

---

