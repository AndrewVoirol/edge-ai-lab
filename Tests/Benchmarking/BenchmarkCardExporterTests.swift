// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - BenchmarkCardExporter Tests

@Suite("BenchmarkCardExporter")
struct BenchmarkCardExporterTests {

    // MARK: - Render Image

    @Test("renderImage — twitterCard produces non-nil image")
    @MainActor
    func testRenderImageTwitterCard() {
        let data = makeTestCardData()
        let image = BenchmarkCardExporter.renderImage(data: data, size: .twitterCard)
        #expect(image != nil)
    }

    @Test("renderImage — instagramSquare produces non-nil image")
    @MainActor
    func testRenderImageInstagramSquare() {
        let data = makeTestCardData()
        let image = BenchmarkCardExporter.renderImage(data: data, size: .instagramSquare)
        #expect(image != nil)
    }

    @Test("renderImage — default produces non-nil image")
    @MainActor
    func testRenderImageDefault() {
        let data = makeTestCardData()
        let image = BenchmarkCardExporter.renderImage(data: data, size: .default)
        #expect(image != nil)
    }

    // MARK: - Render PNG

    @Test("renderPNG — produces non-nil data")
    @MainActor
    func testRenderPNG() {
        let data = makeTestCardData()
        let pngData = BenchmarkCardExporter.renderPNG(data: data, size: .twitterCard)
        #expect(pngData != nil)

        // Verify PNG header (magic bytes)
        if let png = pngData {
            #expect(png.count > 8)
            let header = Array(png.prefix(4))
            #expect(header[0] == 0x89)
            #expect(header[1] == 0x50)  // P
            #expect(header[2] == 0x4E)  // N
            #expect(header[3] == 0x47)  // G
        }
    }

    // MARK: - Render All Sizes

    @Test("renderAllSizes — produces images for all card sizes")
    @MainActor
    func testRenderAllSizes() {
        let data = makeTestCardData()
        let allImages = BenchmarkCardExporter.renderAllSizes(data: data)
        #expect(allImages.count == CardSize.allCases.count)
    }

    // MARK: - Legacy Renderer

    @Test("BenchmarkCardRenderer — backward-compatible renderImage")
    @MainActor
    func testLegacyRenderer() {
        let data = makeTestCardData()
        let image = BenchmarkCardRenderer.renderImage(data: data)
        #expect(image != nil)
    }

    @Test("BenchmarkCardRenderer — backward-compatible renderPNG")
    @MainActor
    func testLegacyRendererPNG() {
        let data = makeTestCardData()
        let pngData = BenchmarkCardRenderer.renderPNG(data: data)
        #expect(pngData != nil)
    }

    // MARK: - Test Helpers

    private func makeTestCardData() -> BenchmarkCardData {
        BenchmarkCardData(
            modelName: "Gemma 4 1B · Text Only",
            modelArchitecture: "Dense 1B",
            backendLabel: "GPU (Metal)",
            deviceName: "MacBook Pro",
            chipName: "arm64e",
            osVersion: "macOS 26.0",
            ramGB: 36,
            decodeSpeed: 42.3,
            prefillSpeed: 128.7,
            ttft: 0.089,
            p95LatencyMs: 16.7,
            medianLatencyMs: 9.8,
            memoryDeltaMB: -245,
            thermalState: .nominal,
            tokenCount: 512,
            timestamp: Date()
        )
    }
}
