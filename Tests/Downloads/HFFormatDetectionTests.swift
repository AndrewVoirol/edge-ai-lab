import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("HF Format Detection Tests")
struct HFFormatDetectionTests {
    
    // MARK: - Format Detection Tests
    
    @Test("detectFormat identifies MLX from author mlx-community")
    func detectFormatMLXCommunity() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "mlx-community/gemma-4-E2B-it-4bit",
            author: "mlx-community",
            siblings: [
                HFSibling(rfilename: "config.json", size: 100, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    @Test("detectFormat identifies MLX from ID pattern containing -mlx")
    func detectFormatMLXSuffix() {
        let browser = HFModelBrowser()
        // Using unsloth/gemma-4-E2B-it-MLX-8bit
        let model = HFModelInfo(
            id: "unsloth/gemma-4-E2B-it-MLX-8bit",
            author: "unsloth",
            siblings: [
                HFSibling(rfilename: "config.json", size: 100, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    @Test("detectFormat identifies MLX from ID pattern containing mlx-")
    func detectFormatMLXPrefix() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "someuser/mlx-gemma-4-E2B-it",
            author: "someuser",
            siblings: [
                HFSibling(rfilename: "config.json", size: 100, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    @Test("detectFormat identifies GGUF from ID pattern -gguf")
    func detectFormatGGUFSuffix() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "unsloth/gemma-4-E2B-it-GGUF",
            author: "unsloth"
        )
        #expect(browser.detectFormat(model) == .gguf)
    }
    
    @Test("detectFormat identifies GGUF from tag gguf")
    func detectFormatGGUFTag() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "someuser/gemma-4-E2B",
            author: "someuser",
            tags: ["text-generation", "gguf"]
        )
        #expect(browser.detectFormat(model) == .gguf)
    }
    
    @Test("detectFormat identifies LiteRT-LM from author litert-community with .litertlm siblings")
    func detectFormatLiteRTLM() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "litert-community/gemma-4-E2B-it",
            author: "litert-community",
            siblings: [
                HFSibling(rfilename: "model.litertlm", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .litertlm)
    }
    
    @Test("detectFormat returns .unknown for a model with no signals")
    func detectFormatUnknown() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "openai/whisper-large-v3",
            author: "openai"
        )
        #expect(browser.detectFormat(model) == .unknown)
    }
    
    @Test("detectFormat identifies MLX from ID pattern without siblings (search endpoint scenario)")
    func detectFormatMLXFromSearchNoSiblings() {
        let browser = HFModelBrowser()
        // This is the exact scenario from the bug report:
        // unsloth MLX models from the search endpoint have no siblings, no library_name, no mlx tag
        let model = HFModelInfo(
            id: "unsloth/gemma-4-E2B-it-MLX-8bit",
            author: "unsloth",
            tags: ["safetensors", "gemma4", "image-text-to-text", "license:apache-2.0", "8-bit"]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    @Test("detectFormat identifies GGUF from ID pattern without siblings (search endpoint scenario)")
    func detectFormatGGUFFromSearchNoSiblings() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "unsloth/gemma-4-E2B-it-GGUF",
            author: "unsloth",
            tags: ["gguf", "gemma4", "image-text-to-text"]
        )
        #expect(browser.detectFormat(model) == .gguf)
    }
    
    @Test("detectFormat identifies MLX from library_name: mlx")
    func detectFormatMLXLibraryName() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "someuser/gemma-4-E2B-it",
            author: "someuser",
            libraryName: "mlx",
            siblings: [
                HFSibling(rfilename: "config.json", size: 100, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    @Test("detectFormat identifies MLX from tag mlx")
    func detectFormatMLXTag() {
        let browser = HFModelBrowser()
        let model = HFModelInfo(
            id: "someuser/gemma-4-E2B-it",
            author: "someuser",
            tags: ["mlx"],
            siblings: [
                HFSibling(rfilename: "config.json", size: 100, lfs: nil),
                HFSibling(rfilename: "model.safetensors", size: 100, lfs: nil)
            ]
        )
        #expect(browser.detectFormat(model) == .mlx)
    }
    
    // MARK: - GGUF Variant Logic Tests
    
    @Test("extractVariants extracts correct quantization labels")
    func extractVariantsLabels() {
        let siblings = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "model-Q8_0.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "model-BF16.gguf", size: 100, lfs: nil)
        ]
        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        
        let quantizations = variants.map { $0.quantization }.sorted()
        #expect(quantizations == ["BF16", "Q4_K_M", "Q8_0"])
    }
    
    @Test("extractVariants excludes mmproj companion files")
    func extractVariantsExcludesMMProj() {
        let siblings = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "model-mmproj-f16.gguf", size: 100, lfs: nil)
        ]
        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        
        #expect(variants.count == 1)
        #expect(variants.first?.quantization == "Q4_K_M")
    }
    
    @Test("extractVariants excludes MTP companion files")
    func extractVariantsExcludesMTP() {
        let siblings = [
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "mtp-model.gguf", size: 100, lfs: nil)
        ]
        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        
        #expect(variants.count == 1)
        #expect(variants.first?.quantization == "Q4_K_M")
    }
    
    @Test("recommendedVariant returns Q4_K_M when available")
    func recommendedVariantQ4KM() {
        let siblings = [
            HFSibling(rfilename: "model-Q8_0.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "model-Q4_K_M.gguf", size: 100, lfs: nil),
            HFSibling(rfilename: "model-Q3_K_M.gguf", size: 100, lfs: nil)
        ]
        let variants = GGUFVariantLogic.extractVariants(from: siblings)
        let recommended = GGUFVariantLogic.recommendedVariant(from: variants)
        
        #expect(recommended?.quantization == "Q4_K_M")
    }
    
    @Test("qualityTier groups correctly")
    func qualityTierGrouping() {
        #expect(GGUFVariantLogic.qualityTier(for: "BF16") == .maximum)
        #expect(GGUFVariantLogic.qualityTier(for: "Q4_K_M") == .recommended)
        #expect(GGUFVariantLogic.qualityTier(for: "Q3_K_S") == .compact)
    }
}

