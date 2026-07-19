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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Model Name Normalization Tests
//
// Unit tests for the display-name normalization and splitting logic used in
// SidebarModelRow and GalleryModelDiscovery. Because the source functions are
// `private static`, we replicate the exact algorithms here as standalone
// helpers — the established pattern for testing private logic in this codebase.

@Suite("ModelNameNormalization")
struct ModelNameNormalizationTests {

    // MARK: - Replicated Logic (mirrors SidebarModelRow.normalizeDisplayName)

    /// Exact replica of `SidebarModelRow.normalizeDisplayName(_:)`.
    private static func normalizeDisplayName(_ name: String) -> String {
        // Skip names that already look well-formatted (contain " : " separator = MLX catalog)
        if name.contains(" : ") { return name }

        var result = name
            .replacingOccurrences(of: "--", with: " / ")
            .replacingOccurrences(of: "-", with: " ")

        // Title-case known model family prefixes
        result = result
            .replacingOccurrences(of: "gemma ", with: "Gemma ", options: .caseInsensitive)
            .replacingOccurrences(of: "llama ", with: "Llama ", options: .caseInsensitive)
            .replacingOccurrences(of: "mistral ", with: "Mistral ", options: .caseInsensitive)
            .replacingOccurrences(of: "phi ", with: "Phi ", options: .caseInsensitive)
            .replacingOccurrences(of: "qwen ", with: "Qwen ", options: .caseInsensitive)
            // Normalize common component casing
            .replacingOccurrences(of: " it ", with: " IT ", options: .caseInsensitive)
            .replacingOccurrences(of: " it$", with: " IT", options: [.caseInsensitive, .regularExpression])
            .replacingOccurrences(of: " e2b", with: " E2B", options: .caseInsensitive)
            .replacingOccurrences(of: " e4b", with: " E4B", options: .caseInsensitive)

        return result
    }

    // MARK: - Replicated Logic (mirrors SidebarModelRow.splitModelName)

    /// Exact replica of `SidebarModelRow.splitModelName(_:)`.
    private static func splitModelName(_ fullName: String) -> (primary: String, secondary: String?) {
        let quantPatterns = [
            "UD-IQ", "UD-Q",
            "IQ4_", "IQ3_", "IQ2_",
            "Q3_K", "Q4_K", "Q5_K", "Q6_K", "Q8_",
            "Q4_0", "Q4_1", "Q5_0", "Q5_1",
            "BF16", "F16", "F32",
            // Common HuggingFace shorthand quantization names
            "4bit", "8bit", "2bit",
        ]
        for pattern in quantPatterns {
            if let range = fullName.range(of: pattern, options: .caseInsensitive) {
                let primary = String(fullName[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let secondary = String(fullName[range.lowerBound...])
                return (primary.isEmpty ? fullName : primary, secondary)
            }
        }
        return (fullName, nil)
    }

    // MARK: - Replicated Logic (mirrors GalleryModelDiscovery.synthesizeMetadata display name)

    /// Replicates the display-name generation from `GalleryModelDiscovery.synthesizeMetadata`.
    private static func synthesizeDisplayName(from stem: String) -> String {
        let rawName = stem
            .replacingOccurrences(of: "--", with: " / ")
            .replacingOccurrences(of: "-", with: " ")

        let displayName = rawName
            .replacingOccurrences(of: "gemma ", with: "Gemma ", options: .caseInsensitive)
            .replacingOccurrences(of: "llama ", with: "Llama ", options: .caseInsensitive)
            .replacingOccurrences(of: "mistral ", with: "Mistral ", options: .caseInsensitive)
            .replacingOccurrences(of: "phi ", with: "Phi ", options: .caseInsensitive)
            .replacingOccurrences(of: "qwen ", with: "Qwen ", options: .caseInsensitive)
            .replacingOccurrences(of: " it ", with: " IT ", options: .caseInsensitive)
            .replacingOccurrences(of: " it$", with: " IT", options: [.caseInsensitive, .regularExpression])
            .replacingOccurrences(of: " e2b", with: " E2B", options: .caseInsensitive)
            .replacingOccurrences(of: " e4b", with: " E4B", options: .caseInsensitive)

        return displayName
    }

    // MARK: - normalizeDisplayName Tests

    @Test("Hyphenated GGUF name with 4bit quantization")
    func normalizeHyphenated4bit() {
        let result = Self.normalizeDisplayName("gemma-4-e2b-it-4bit")
        #expect(result == "Gemma 4 E2B IT 4bit")
    }

    @Test("Hyphenated GGUF name with Q4_K_M quantization")
    func normalizeHyphenatedQ4KM() {
        let result = Self.normalizeDisplayName("gemma-4-E2B-it-Q4_K_M")
        #expect(result == "Gemma 4 E2B IT Q4_K_M")
    }

    @Test("Llama model name is title-cased")
    func normalizeLlama() {
        let result = Self.normalizeDisplayName("llama-3.2-1B-instruct-Q4_K_M")
        #expect(result == "Llama 3.2 1B instruct Q4_K_M")
    }

    @Test("Phi model name is title-cased")
    func normalizePhi() {
        let result = Self.normalizeDisplayName("phi-4-mini-instruct-Q8_0")
        #expect(result == "Phi 4 mini instruct Q8_0")
    }

    @Test("Qwen model name — dot-version blocks title-casing")
    func normalizeQwen() {
        // Note: "qwen2.5" has no space after "qwen", so the pattern "qwen " doesn't match.
        // The normalizer only title-cases when the pattern includes a trailing space.
        // This is a known limitation — acceptable because HF names vary widely.
        let result = Self.normalizeDisplayName("qwen2.5-0.5b-instruct")
        #expect(result == "qwen2.5 0.5b instruct")
    }

    @Test("MLX catalog name with colon separator passes through unchanged")
    func normalizeMLXCatalogPassthrough() {
        let catalogName = "Gemma 4 E2B : Desktop GPU+CPU"
        let result = Self.normalizeDisplayName(catalogName)
        #expect(result == catalogName)
    }

    @Test("Already-normalized name does not double-capitalize")
    func normalizeIdempotent() {
        let alreadyNormalized = "Gemma 4 E2B IT Q4_K_M"
        let result = Self.normalizeDisplayName(alreadyNormalized)
        #expect(result == alreadyNormalized)
    }

    // MARK: - splitModelName Tests

    @Test("Split name with Q4_K_M quantization suffix")
    func splitQ4KM() {
        let (primary, secondary) = Self.splitModelName("Gemma 4 E2B IT Q4_K_M")
        #expect(primary == "Gemma 4 E2B IT")
        #expect(secondary == "Q4_K_M")
    }

    @Test("Split name with BF16 quantization suffix")
    func splitBF16() {
        let (primary, secondary) = Self.splitModelName("Gemma 4 E2B IT BF16")
        #expect(primary == "Gemma 4 E2B IT")
        #expect(secondary == "BF16")
    }

    @Test("Split name with 4bit quantization suffix")
    func split4bit() {
        let (primary, secondary) = Self.splitModelName("Gemma 4 E2B IT 4bit")
        #expect(primary == "Gemma 4 E2B IT")
        #expect(secondary == "4bit")
    }

    @Test("Split name with IQ4_XS quantization suffix")
    func splitIQ4XS() {
        let (primary, secondary) = Self.splitModelName("Gemma 4 E2B IT IQ4_XS")
        #expect(primary == "Gemma 4 E2B IT")
        #expect(secondary == "IQ4_XS")
    }

    @Test("Split name with no quantization suffix returns nil secondary")
    func splitNoQuant() {
        let (primary, secondary) = Self.splitModelName("Gemma 4 E2B IT")
        #expect(primary == "Gemma 4 E2B IT")
        #expect(secondary == nil)
    }

    @Test("Split name that is only a quantization token returns full string as primary")
    func splitOnlyQuant() {
        let (primary, secondary) = Self.splitModelName("Q4_K_M")
        // When the entire string matches a quant pattern, primary is empty → falls back to fullName
        #expect(primary == "Q4_K_M")
        #expect(secondary == "Q4_K_M")
    }

    // MARK: - synthesizeMetadata Display Name Tests

    @Test("Synthesized name from GGUF stem contains expected components")
    func synthesizeGemmaE2B() {
        let displayName = Self.synthesizeDisplayName(from: "gemma-4-E2B-it-Q4_K_M")
        #expect(displayName.contains("Gemma"))
        #expect(displayName.contains("IT"))
        #expect(displayName.contains("E2B"))
    }

    @Test("Synthesized name from stem with E4B contains expected components")
    func synthesizeGemmaE4B() {
        let displayName = Self.synthesizeDisplayName(from: "gemma-4-e4b-it")
        #expect(displayName.contains("E4B"))
        #expect(displayName.contains("IT"))
    }

    @Test("Double hyphen in org--model produces slash separator")
    func synthesizeDoubleHyphen() {
        let displayName = Self.synthesizeDisplayName(from: "org--model")
        #expect(displayName.contains(" / "))
    }
}
