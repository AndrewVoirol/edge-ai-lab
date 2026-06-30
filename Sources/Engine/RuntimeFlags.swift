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

// MARK: - RuntimeFlags

/// Runtime-agnostic configuration flags for inference engines.
///
/// Replaces `ExperimentalFlagsState` at the `InferenceEngine` protocol boundary.
/// `ExperimentalFlagsState` continues to exist internally for LiteRT-LM SDK bridging
/// inside `LiteRTEngineAdapter`, but no longer appears in the public API surface.
///
/// ## Design
///
/// - **Common flags** apply to all runtimes (LiteRT-LM, MLX, future GGUF).
/// - **Runtime-specific flags** are stored as optionals — each adapter reads only its own
///   fields and ignores the rest.
/// - **Backward-compatible JSON decoding** via `init(from decoder:)` with `decodeIfPresent`
///   ensures that `MetricsStore.Entry.flags` persisted as old `ExperimentalFlagsState` JSON
///   decodes correctly into `RuntimeFlags`.
///
/// ## Migration
///
/// - Protocol boundary: `ModelLoadConfig.experimentalFlags` → `ModelLoadConfig.runtimeFlags`
/// - Consumers: `ExperimentalFlagsState` → `RuntimeFlags` everywhere except `LiteRTEngineAdapter`
/// - `LiteRTEngineAdapter` internally converts via `toLiteRTFlags()` before calling the SDK
struct RuntimeFlags: Codable, Equatable, Sendable {

    // MARK: - Common Flags (applicable to all runtimes)

    /// Whether benchmark instrumentation is enabled.
    var enableBenchmark: Bool = false

    /// Whether thinking mode is enabled in the UI.
    /// When true, the model's `<think>...</think>` output is parsed and displayed
    /// separately from the response.
    var enableThinking: Bool = true

    /// Whether tool calling is enabled for the current session.
    var enableToolCalling: Bool = false

    /// Whether Wikipedia search and Apple Maps grounding/rendering are enabled.
    var enableAgentSkills: Bool = false

    // MARK: - LiteRT-Specific (stored but only consumed by LiteRTEngineAdapter)

    /// Whether speculative decoding is enabled. LiteRT-LM only.
    var enableSpeculativeDecoding: Bool? = nil

    /// Whether conversation-constrained decoding is enabled. LiteRT-LM only.
    var enableConversationConstrainedDecoding: Bool = false

    /// Maximum visual token budget for image inputs. LiteRT-LM only.
    var visualTokenBudget: Int32? = nil

    // MARK: - MLX-Specific (stored but only consumed by MLXEngineAdapter)

    /// Metal memory limit in bytes. Controls `Memory.memoryLimit`.
    /// `nil` = use default (system-managed).
    var metalMemoryLimit: Int? = nil

    /// Metal buffer cache limit in bytes. Controls `Memory.cacheLimit`.
    /// `nil` = use default (512 MB).
    var metalCacheLimit: Int? = nil

    /// Compute precision: `"float16"` or `"float32"`.
    /// `nil` = use model default (usually float16).
    var computePrecision: String? = nil

    /// Maximum image resolution (longest edge, in pixels) for VLM preprocessing.
    /// `nil` = let the VLM processor decide automatically.
    var maxImageResolution: Int? = nil

    /// Maximum image token budget for VLM models.
    /// `nil` = let the VLM processor decide automatically.
    var maxImageTokenBudget: Int? = nil

    // MARK: - Initialization

    /// Default initializer with sensible defaults for all fields.
    init(
        enableBenchmark: Bool = false,
        enableThinking: Bool = true,
        enableToolCalling: Bool = false,
        enableAgentSkills: Bool = false,
        enableSpeculativeDecoding: Bool? = nil,
        enableConversationConstrainedDecoding: Bool = false,
        visualTokenBudget: Int32? = nil,
        metalMemoryLimit: Int? = nil,
        metalCacheLimit: Int? = nil,
        computePrecision: String? = nil,
        maxImageResolution: Int? = nil,
        maxImageTokenBudget: Int? = nil
    ) {
        self.enableBenchmark = enableBenchmark
        self.enableThinking = enableThinking
        self.enableToolCalling = enableToolCalling
        self.enableAgentSkills = enableAgentSkills
        self.enableSpeculativeDecoding = enableSpeculativeDecoding
        self.enableConversationConstrainedDecoding = enableConversationConstrainedDecoding
        self.visualTokenBudget = visualTokenBudget
        self.metalMemoryLimit = metalMemoryLimit
        self.metalCacheLimit = metalCacheLimit
        self.computePrecision = computePrecision
        self.maxImageResolution = maxImageResolution
        self.maxImageTokenBudget = maxImageTokenBudget
    }

    // MARK: - Backward-Compatible JSON Decoding

    /// Custom decoder supporting both `RuntimeFlags` JSON and old `ExperimentalFlagsState` JSON.
    ///
    /// Old `ExperimentalFlagsState` JSON contains:
    /// `enableBenchmark`, `enableSpeculativeDecoding`, `enableConversationConstrainedDecoding`,
    /// `visualTokenBudget`, `enableThinking`, `enableToolCalling`, `enableAgentSkills`
    ///
    /// New `RuntimeFlags` JSON adds:
    /// `metalMemoryLimit`, `metalCacheLimit`, `computePrecision`,
    /// `maxImageResolution`, `maxImageTokenBudget`
    ///
    /// All new fields use `decodeIfPresent` with defaults, so old JSON decodes cleanly.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Common flags (present in both old and new format)
        enableBenchmark = try container.decodeIfPresent(Bool.self, forKey: .enableBenchmark) ?? false
        enableThinking = try container.decodeIfPresent(Bool.self, forKey: .enableThinking) ?? true
        enableToolCalling = try container.decodeIfPresent(Bool.self, forKey: .enableToolCalling) ?? false
        enableAgentSkills = try container.decodeIfPresent(Bool.self, forKey: .enableAgentSkills) ?? false

        // LiteRT-specific (present in old format)
        enableSpeculativeDecoding = try container.decodeIfPresent(Bool.self, forKey: .enableSpeculativeDecoding)
        enableConversationConstrainedDecoding = try container.decodeIfPresent(
            Bool.self, forKey: .enableConversationConstrainedDecoding) ?? false
        visualTokenBudget = try container.decodeIfPresent(Int32.self, forKey: .visualTokenBudget)

        // MLX-specific (new — absent from old format, defaults to nil)
        metalMemoryLimit = try container.decodeIfPresent(Int.self, forKey: .metalMemoryLimit)
        metalCacheLimit = try container.decodeIfPresent(Int.self, forKey: .metalCacheLimit)
        computePrecision = try container.decodeIfPresent(String.self, forKey: .computePrecision)
        maxImageResolution = try container.decodeIfPresent(Int.self, forKey: .maxImageResolution)
        maxImageTokenBudget = try container.decodeIfPresent(Int.self, forKey: .maxImageTokenBudget)
    }

    // MARK: - ExperimentalFlagsState Conversion

    /// Convert to LiteRT-LM's `ExperimentalFlagsState` for backward compatibility.
    ///
    /// Used internally by `LiteRTEngineAdapter` to bridge to the LiteRT-LM SDK,
    /// which requires `ExperimentalFlagsState`.
    func toLiteRTFlags() -> ExperimentalFlagsState {
        ExperimentalFlagsState(
            enableBenchmark: enableBenchmark,
            enableSpeculativeDecoding: enableSpeculativeDecoding,
            enableConversationConstrainedDecoding: enableConversationConstrainedDecoding,
            visualTokenBudget: visualTokenBudget,
            enableThinking: enableThinking,
            enableToolCalling: enableToolCalling,
            enableAgentSkills: enableAgentSkills
        )
    }

    /// Create `RuntimeFlags` from an existing `ExperimentalFlagsState`.
    ///
    /// Used for migration — converts old flag values to the new runtime-agnostic type.
    init(from liteRTFlags: ExperimentalFlagsState) {
        self.enableBenchmark = liteRTFlags.enableBenchmark
        self.enableThinking = liteRTFlags.enableThinking
        self.enableToolCalling = liteRTFlags.enableToolCalling
        self.enableAgentSkills = liteRTFlags.enableAgentSkills
        self.enableSpeculativeDecoding = liteRTFlags.enableSpeculativeDecoding
        self.enableConversationConstrainedDecoding = liteRTFlags.enableConversationConstrainedDecoding
        self.visualTokenBudget = liteRTFlags.visualTokenBudget
        // MLX-specific fields default to nil
        self.metalMemoryLimit = nil
        self.metalCacheLimit = nil
        self.computePrecision = nil
        self.maxImageResolution = nil
        self.maxImageTokenBudget = nil
    }

    // MARK: - Convenience

    /// Captures the current state from the global `ExperimentalFlags` statics.
    ///
    /// Mirrors `ExperimentalFlagsState.captureCurrentState()` but returns `RuntimeFlags`.
    static func captureCurrentState() -> RuntimeFlags {
        RuntimeFlags(from: ExperimentalFlagsState.captureCurrentState())
    }
}
