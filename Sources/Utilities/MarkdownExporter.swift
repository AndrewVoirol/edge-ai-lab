// Copyright 2026 Andrew Voirol. Apache-2.0
// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

// MARK: - Markdown Exporter

/// Generates GitHub-flavored Markdown tables and templates from benchmark data.
/// Extracted into an enum namespace for testability — pure functions, no state.
enum MarkdownExporter {

    /// Generate a Markdown table from benchmark entries.
    ///
    /// Example output:
    /// ```
    /// | Model | Device | Decode (tok/s) | TTFT (s) | Prefill (tok/s) | Platform |
    /// |-------|--------|----------------|----------|-----------------|----------|
    /// | Gemma 4 1B | MacBook Pro | 42.3 | 0.089 | 128.7 | macOS |
    /// ```
    static func generateBenchmarkTable(entries: [MetricsStore.Entry]) -> String {
        guard !entries.isEmpty else {
            return "_No benchmark data available._"
        }

        var lines: [String] = []

        // Header
        lines.append("| Model | Device | Decode (tok/s) | TTFT (s) | Prefill (tok/s) | Platform |")
        lines.append("|-------|--------|----------------|----------|-----------------|----------|")

        // Rows
        for entry in entries {
            let model = escapePipes(entry.model)
            let device = escapePipes(entry.device)
            let decode = String(format: "%.1f", entry.metrics.decodeTokensPerSecond)
            let ttft = String(format: "%.3f", entry.metrics.ttftSeconds)
            let prefill = String(format: "%.1f", entry.metrics.prefillTokensPerSecond)
            let platform = escapePipes(entry.platform)

            lines.append("| \(model) | \(device) | \(decode) | \(ttft) | \(prefill) | \(platform) |")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate a full GitHub Discussion/Issue template from a single entry.
    ///
    /// Includes device info, model info, all metrics, and Edge AI Lab version.
    static func generateGitHubTemplate(entry: MetricsStore.Entry) -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"

        var sections: [String] = []

        // Title
        sections.append("## Benchmark Result: \(escapePipes(entry.model))")
        sections.append("")

        // Device Info
        sections.append("### Device")
        sections.append("")
        sections.append("| Property | Value |")
        sections.append("|----------|-------|")
        sections.append("| **Device** | \(escapePipes(entry.device)) |")
        sections.append("| **Platform** | \(escapePipes(entry.platform)) |")
        sections.append("| **Edge AI Lab** | v\(version) (\(build)) |")
        sections.append("| **Timestamp** | \(entry.timestamp) |")
        sections.append("")

        // Core Metrics
        sections.append("### Performance Metrics")
        sections.append("")
        sections.append("| Metric | Value |")
        sections.append("|--------|-------|")
        sections.append("| **Decode Speed** | \(String(format: "%.1f", entry.metrics.decodeTokensPerSecond)) tok/s |")
        sections.append("| **Prefill Speed** | \(String(format: "%.1f", entry.metrics.prefillTokensPerSecond)) tok/s |")
        sections.append("| **TTFT** | \(String(format: "%.3f", entry.metrics.ttftSeconds)) s |")
        sections.append("| **Init Time** | \(String(format: "%.2f", entry.metrics.initTimeSeconds)) s |")
        sections.append("| **Decode Tokens** | \(entry.metrics.lastDecodeTokenCount) |")
        sections.append("| **Prefill Tokens** | \(entry.metrics.lastPrefillTokenCount) |")

        // Optional extended metrics
        if let p95 = entry.metrics.p95TokenLatencyMs {
            sections.append("| **P95 Latency** | \(String(format: "%.1f", p95)) ms |")
        }
        if let median = entry.metrics.medianTokenLatencyMs {
            sections.append("| **Median Latency** | \(String(format: "%.1f", median)) ms |")
        }
        if let startMem = entry.metrics.availableMemoryAtStartMB,
           let endMem = entry.metrics.availableMemoryAtEndMB {
            let delta = startMem - endMem
            sections.append("| **Memory Δ** | \(String(format: "%+.0f", -delta)) MB |")
        }
        if let bandwidth = entry.metrics.estimatedMemoryBandwidthGBps {
            sections.append("| **Est. Bandwidth** | \(String(format: "%.2f", bandwidth)) GB/s |")
        }
        sections.append("")

        // Flags
        sections.append("### Configuration")
        sections.append("")
        sections.append("| Flag | Value |")
        sections.append("|------|-------|")
        sections.append("| Benchmark Mode | \(entry.flags.enableBenchmark ? "✅" : "❌") |")
        if let spec = entry.flags.enableSpeculativeDecoding {
            sections.append("| Speculative Decoding | \(spec ? "✅" : "❌") |")
        }
        sections.append("| Thinking | \(entry.flags.enableThinking ? "✅" : "❌") |")
        sections.append("| Tool Calling | \(entry.flags.enableToolCalling ? "✅" : "❌") |")
        sections.append("")

        // Footer
        sections.append("---")
        sections.append("_Generated by [Edge AI Lab](https://github.com/AndrewVoirol/edge-ai-lab) v\(version)_")

        return sections.joined(separator: "\n")
    }

    /// Escape pipe characters in strings to prevent markdown table breakage.
    static func escapePipes(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
    }
}
