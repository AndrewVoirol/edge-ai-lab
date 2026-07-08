// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

/// Testable helper for detecting whether a model directory contains a VLM.
///
/// Extracted from `MLXEngineAdapter` following the project pattern of putting testable
/// logic into `enum` namespaces with `static` methods (e.g., `EvalRunnerLogic`,
/// `ModelDetailFormatters`). This prevents accidental instantiation while keeping
/// related logic grouped and accessible to unit tests.
///
/// ## Detection Strategy
///
/// VLMs (Gemma 4, Qwen-VL, PaliGemma) ship with `processor_config.json` or
/// `preprocessor_config.json` alongside their weights and `config.json`.
/// Text-only LLMs do not have these files. This matches the detection pattern
/// used in `HFModelBrowser.swift` for download filtering.
enum MLXVLMDetectionHelper {

    /// Checks whether a local model directory is a VLM by looking for vision processor config files.
    ///
    /// - Parameter directory: The root directory of the MLX model (containing `config.json`,
    ///   `*.safetensors`, and optionally `processor_config.json`).
    /// - Returns: `true` if the directory contains `processor_config.json` or
    ///   `preprocessor_config.json`, indicating a VLM that should be loaded via `VLMModelFactory`.
    static func isVLMModel(at directory: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: directory.appendingPathComponent("processor_config.json").path)
            || fm.fileExists(atPath: directory.appendingPathComponent("preprocessor_config.json").path)
    }
}
