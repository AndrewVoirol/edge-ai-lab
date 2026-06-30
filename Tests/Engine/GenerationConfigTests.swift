// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("GenerationConfig")
struct GenerationConfigTests {

    // MARK: - Defaults

    @Test("default config has sensible values")
    func defaults() {
        let config = GenerationConfig.default
        #expect(config.maxTokens == 512)
        #expect(config.temperature == 0.7)
        #expect(config.topP == 0.9)
        #expect(config.topK == 40)
        #expect(config.repetitionPenalty == nil)
        #expect(config.seed == nil)
        #expect(config.imageData == nil)
        #expect(config.diffusionSteps == nil)
        #expect(config.diffusionSchedule == nil)
    }

    // MARK: - Image Data

    @Test("imageData can hold multiple images")
    func multipleImages() {
        let img1 = Data([0xFF, 0xD8, 0xFF])  // JPEG magic bytes
        let img2 = Data([0x89, 0x50, 0x4E])  // PNG magic bytes
        var config = GenerationConfig.default
        config.imageData = [img1, img2]
        #expect(config.imageData?.count == 2)
        #expect(config.imageData?[0] == img1)
        #expect(config.imageData?[1] == img2)
    }

    @Test("nil imageData means text-only generation")
    func nilImageData() {
        let config = GenerationConfig.default
        #expect(config.imageData == nil)
    }

    // MARK: - Equatable

    @Test("Equatable: identical configs are equal")
    func equatable() {
        let a = GenerationConfig(maxTokens: 256, temperature: 0.5)
        let b = GenerationConfig(maxTokens: 256, temperature: 0.5)
        #expect(a == b)
    }

    @Test("Equatable: different maxTokens are not equal")
    func notEqual() {
        let a = GenerationConfig(maxTokens: 256)
        let b = GenerationConfig(maxTokens: 512)
        #expect(a != b)
    }

    @Test("Equatable: same imageData are equal")
    func imageDataEquality() {
        let img = Data([0xFF, 0xD8, 0xFF])
        let a = GenerationConfig(imageData: [img])
        let b = GenerationConfig(imageData: [img])
        #expect(a == b)
    }

    @Test("Equatable: nil vs non-nil imageData are not equal")
    func imageDataInequality() {
        let img = Data([0xFF, 0xD8, 0xFF])
        let a = GenerationConfig()
        let b = GenerationConfig(imageData: [img])
        #expect(a != b)
    }

    // MARK: - Custom Init

    @Test("custom init preserves all fields including imageData")
    func customInit() {
        let img = Data([0x00, 0x01])
        let config = GenerationConfig(
            maxTokens: 1024,
            temperature: 0.9,
            topP: 0.95,
            topK: 50,
            repetitionPenalty: 1.1,
            seed: 42,
            imageData: [img],
            diffusionSteps: 20,
            diffusionSchedule: "cosine"
        )
        #expect(config.maxTokens == 1024)
        #expect(config.temperature == 0.9)
        #expect(config.topP == 0.95)
        #expect(config.topK == 50)
        #expect(config.repetitionPenalty == 1.1)
        #expect(config.seed == 42)
        #expect(config.imageData?.count == 1)
        #expect(config.diffusionSteps == 20)
        #expect(config.diffusionSchedule == "cosine")
    }
}
