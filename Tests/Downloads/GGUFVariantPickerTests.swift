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

// MARK: - Quantization Extraction

@Suite("GGUFVariantLogic — Quantization Extraction")
struct QuantizationExtractionTests {

    @Test("Q4_K_M extracted from standard filename")
    func q4kmStandard() {
        let result = GGUFVariantLogic.extractQuantization(from: "gemma-4-E2B-it-Q4_K_M.gguf")
        #expect(result == "Q4_K_M")
    }

    @Test("Q8_0 extracted from dot-separated filename")
    func q80DotSeparated() {
        let result = GGUFVariantLogic.extractQuantization(from: "model.Q8_0.gguf")
        #expect(result == "Q8_0")
    }

    @Test("BF16 extracted")
    func bf16() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-BF16.gguf")
        #expect(result == "BF16")
    }

    @Test("F16 extracted")
    func f16() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-F16.gguf")
        #expect(result == "F16")
    }

    @Test("Q5_K_S extracted")
    func q5ks() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-Q5_K_S.gguf")
        #expect(result == "Q5_K_S")
    }

    @Test("Q6_K extracted")
    func q6k() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-Q6_K.gguf")
        #expect(result == "Q6_K")
    }

    @Test("Unknown for plain filename")
    func unknownPlain() {
        let result = GGUFVariantLogic.extractQuantization(from: "model.gguf")
        #expect(result == "Unknown")
    }

    @Test("IQ variant extracted")
    func iqVariant() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-IQ4_XS.gguf")
        #expect(result == "IQ4_XS")
    }

    @Test("Case insensitive extraction")
    func caseInsensitive() {
        let result = GGUFVariantLogic.extractQuantization(from: "model-q4_k_m.gguf")
        #expect(result == "Q4_K_M")
    }
}

// MARK: - Quality Tiers

@Suite("GGUFVariantLogic — Quality Tiers")
struct QualityTierTests {

    @Test("BF16 is maximum quality")
    func bf16Maximum() {
        #expect(GGUFVariantLogic.qualityTier(for: "BF16") == .maximum)
    }

    @Test("Q8_0 is maximum quality")
    func q80Maximum() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q8_0") == .maximum)
    }

    @Test("Q4_K_M is recommended")
    func q4kmRecommended() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q4_K_M") == .recommended)
    }

    @Test("Q5_K_M is recommended")
    func q5kmRecommended() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q5_K_M") == .recommended)
    }

    @Test("Q6_K is recommended")
    func q6kRecommended() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q6_K") == .recommended)
    }

    @Test("Q3_K_M is compact")
    func q3kmCompact() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q3_K_M") == .compact)
    }

    @Test("Q2_K is compact")
    func q2kCompact() {
        #expect(GGUFVariantLogic.qualityTier(for: "Q2_K") == .compact)
    }

    @Test("IQ4_XS is compact")
    func iq4xsCompact() {
        #expect(GGUFVariantLogic.qualityTier(for: "IQ4_XS") == .compact)
    }

    @Test("Tier ordering: maximum < recommended < compact")
    func tierOrdering() {
        #expect(GGUFVariant.QualityTier.maximum < .recommended)
        #expect(GGUFVariant.QualityTier.recommended < .compact)
    }
}

// MARK: - Variant Extraction

@Suite("GGUFVariantLogic — Variant Extraction")
struct VariantExtractionTests {

    @Test("Extracts model files, excludes companions")
    func excludesCompanions() {
        let siblings: [HFSibling] = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 3_000_000_000, lfs: nil),
            HFSibling(rfilename: "model-Q8_0.gguf", size: 5_000_000_000, lfs: nil),
            HFSibling(rfilename: "mmproj-model.gguf", size: 500_000_000, lfs: nil),
            HFSibling(rfilename: "mtp0-model-Q4_K_M.gguf", size: 200_000_000, lfs: nil),
            HFSibling(rfilename: "config.json", size: 1_000, lfs: nil),
        ]

        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        #expect(variants.count == 2)
        #expect(variants.allSatisfy { !$0.filename.contains("mmproj") })
        #expect(variants.allSatisfy { !$0.filename.hasPrefix("mtp") })
    }

    @Test("Sorted by tier then size descending")
    func sortedByTierThenSize() {
        let siblings: [HFSibling] = [
            HFSibling(rfilename: "model-Q3_K_M.gguf", size: 2_000_000_000, lfs: nil),
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 3_000_000_000, lfs: nil),
            HFSibling(rfilename: "model-BF16.gguf", size: 8_000_000_000, lfs: nil),
        ]

        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        #expect(variants.count == 3)
        #expect(variants[0].quantization == "BF16")       // maximum first
        #expect(variants[1].quantization == "Q4_K_M")     // recommended
        #expect(variants[2].quantization == "Q3_K_M")     // compact last
    }

    @Test("Q4_K_M is marked as recommended")
    func q4kmIsRecommended() {
        let siblings: [HFSibling] = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 3_000_000_000, lfs: nil),
            HFSibling(rfilename: "model-Q5_K_M.gguf", size: 4_000_000_000, lfs: nil),
        ]

        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        let q4 = variants.first(where: { $0.quantization == "Q4_K_M" })
        let q5 = variants.first(where: { $0.quantization == "Q5_K_M" })
        #expect(q4?.isRecommended == true)
        #expect(q5?.isRecommended == false)
    }

    @Test("Single variant means no picker needed")
    func singleVariantNoPicker() {
        let variants = [GGUFVariant(
            id: "model.gguf", filename: "model.gguf",
            quantization: "Q4_K_M", sizeBytes: 3_000_000_000,
            tier: .recommended, isRecommended: true
        )]
        #expect(GGUFVariantLogic.needsPicker(variants: variants) == false)
    }

    @Test("Multiple variants need picker")
    func multipleVariantsNeedPicker() {
        let variants = [
            GGUFVariant(id: "a.gguf", filename: "a.gguf", quantization: "Q4_K_M", sizeBytes: 3_000_000_000, tier: .recommended, isRecommended: true),
            GGUFVariant(id: "b.gguf", filename: "b.gguf", quantization: "Q8_0", sizeBytes: 5_000_000_000, tier: .maximum, isRecommended: false),
        ]
        #expect(GGUFVariantLogic.needsPicker(variants: variants) == true)
    }

    @Test("recommendedVariant selects Q4_K_M")
    func recommendedVariant() {
        let variants = [
            GGUFVariant(id: "a.gguf", filename: "a.gguf", quantization: "Q8_0", sizeBytes: 5_000_000_000, tier: .maximum, isRecommended: false),
            GGUFVariant(id: "b.gguf", filename: "b.gguf", quantization: "Q4_K_M", sizeBytes: 3_000_000_000, tier: .recommended, isRecommended: true),
            GGUFVariant(id: "c.gguf", filename: "c.gguf", quantization: "Q3_K_M", sizeBytes: 2_000_000_000, tier: .compact, isRecommended: false),
        ]
        let rec = GGUFVariantLogic.recommendedVariant(from: variants)
        #expect(rec?.quantization == "Q4_K_M")
    }

    @Test("Uses LFS size when sibling size is nil")
    func usesLfsSize() {
        let siblings: [HFSibling] = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: nil, lfs: HFLFSInfo(oid: "abc", size: 3_000_000_000, pointerSize: 132)),
        ]

        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        #expect(variants.first?.sizeBytes == 3_000_000_000)
    }
}
