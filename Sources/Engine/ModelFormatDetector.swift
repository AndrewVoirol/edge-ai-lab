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

// MARK: - ModelFormatDetector

/// Consolidates format detection logic for both local model paths and
/// HuggingFace model metadata.
///
/// Uses an `enum` namespace (no instantiation) with `static` methods
/// for easy testability outside of Views.
///
/// ## Local Path Detection
///
/// Inspects file extensions and directory contents:
/// - `.litertlm` / `.task` → `.litertlm`
/// - `.gguf` → `.gguf`
/// - Directory with `config.json` + `*.safetensors` → `.mlx`
///
/// ## HuggingFace Metadata Detection
///
/// Priority order: `libraryName` → `tags` → file siblings → model ID → `nil`
enum ModelFormatDetector {

    // MARK: - Local Path Detection

    /// Detect the `RuntimeType` for a model at the given local filesystem URL.
    ///
    /// - Parameter url: A file or directory URL pointing to the model on disk.
    /// - Returns: The detected `RuntimeType`, or `nil` if the format is unrecognized.
    static func detectFormat(at url: URL) -> RuntimeType? {
        let ext = url.pathExtension.lowercased()

        // Single-file model formats by extension
        switch ext {
        case "litertlm", "task":
            return .litertlm
        case "gguf":
            return .gguf
        default:
            break
        }

        // Directory-based detection: MLX model directories contain config.json + *.safetensors
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }

        return detectMLXDirectory(at: url) ? .mlx : nil
    }

    /// Check whether a directory contains the hallmarks of an MLX model:
    /// a `config.json` file and at least one `.safetensors` weight shard.
    ///
    /// - Parameter directoryURL: The directory to inspect.
    /// - Returns: `true` if the directory matches the MLX model layout.
    static func detectMLXDirectory(at directoryURL: URL) -> Bool {
        let fm = FileManager.default
        let configURL = directoryURL.appendingPathComponent("config.json")
        guard fm.fileExists(atPath: configURL.path) else { return false }

        // Check for at least one .safetensors file (weight shard)
        guard let contents = try? fm.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return false
        }

        return contents.contains { $0.pathExtension.lowercased() == "safetensors" }
    }

    // MARK: - HuggingFace Metadata Detection

    /// Detect the `RuntimeType` from HuggingFace model metadata.
    ///
    /// Priority order:
    /// 1. `libraryName` (most reliable — set by repo owner)
    /// 2. `tags` (often includes "litert", "mlx", "gguf")
    /// 3. File siblings (inspect actual filenames in the repo)
    /// 4. Model ID naming conventions (e.g., "litert-lm" in ID, "mlx-community" author)
    /// 5. `nil` if no signal is found
    ///
    /// - Parameter model: The HuggingFace model info from the API.
    /// - Returns: The detected `RuntimeType`, or `nil` if the format is unrecognized.
    static func detectFormat(from model: HFModelInfo) -> RuntimeType? {
        // 1. libraryName — most authoritative signal
        if let runtimeType = detectFromLibraryName(model.libraryName) {
            return runtimeType
        }

        // 2. Tags
        if let runtimeType = detectFromTags(model.tags) {
            return runtimeType
        }

        // 3. File siblings (available from detail endpoint)
        if let siblings = model.siblings,
           let runtimeType = detectFromSiblings(siblings) {
            return runtimeType
        }

        // 4. Model ID naming conventions
        if let runtimeType = detectFromModelId(model.id, author: model.author) {
            return runtimeType
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Match `library_name` field from HuggingFace API to a runtime type.
    private static func detectFromLibraryName(_ libraryName: String?) -> RuntimeType? {
        guard let lib = libraryName?.lowercased() else { return nil }

        if lib.contains("litert") { return .litertlm }
        if lib == "mlx" { return .mlx }
        if lib == "gguf" || lib.contains("llama.cpp") { return .gguf }

        return nil
    }

    /// Scan HuggingFace tags for runtime type signals.
    private static func detectFromTags(_ tags: [String]) -> RuntimeType? {
        for tag in tags {
            let lower = tag.lowercased()
            if lower.contains("litert") { return .litertlm }
            if lower == "mlx" { return .mlx }
            if lower == "gguf" { return .gguf }
        }
        return nil
    }

    /// Inspect file siblings (repository file listing) for format-specific files.
    private static func detectFromSiblings(_ siblings: [HFSibling]) -> RuntimeType? {
        let filenames = siblings.map(\.rfilename)

        // LiteRT-LM: single .litertlm or .task archive
        if filenames.contains(where: { $0.hasSuffix(".litertlm") || $0.hasSuffix(".task") }) {
            return .litertlm
        }

        // GGUF: quantized model file
        if filenames.contains(where: { $0.hasSuffix(".gguf") }) {
            return .gguf
        }

        // MLX: config.json + *.safetensors weight shards
        let hasConfig = filenames.contains("config.json")
        let hasSafetensors = filenames.contains(where: { $0.hasSuffix(".safetensors") })
        if hasConfig && hasSafetensors {
            return .mlx
        }

        return nil
    }

    /// Infer from model ID and author naming conventions.
    private static func detectFromModelId(_ modelId: String, author: String) -> RuntimeType? {
        let lowerId = modelId.lowercased()
        let lowerAuthor = author.lowercased()

        if lowerId.contains("litert-lm") || lowerId.contains("litert_lm") {
            return .litertlm
        }
        if lowerAuthor == "mlx-community" || lowerId.contains("-mlx") {
            return .mlx
        }
        if lowerId.contains("-gguf") || lowerId.hasSuffix(".gguf") {
            return .gguf
        }

        return nil
    }
}
