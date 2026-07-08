// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for the sampler reload optimization in `ModelSessionController`.
///
/// MLX's `ChatSession.generateParameters` is a mutable public var — sampler changes
/// (temperature, topK, topP, seed) are applied per-generation in `generateStream()`.
/// A full engine reload is unnecessary. LiteRT bakes `SamplerConfig` at init time
/// and genuinely needs a reload.
@Suite("MLX Sampler Reload Optimization")
struct MLXSamplerReloadTests {

    // MARK: - applySamplerSettingsInPlace

    @Test("MLX engine returns true — sampler changes applied in-place without reload")
    @MainActor
    func testApplySamplerInPlace_MLXEngine_ReturnsTrue() async throws {
        let mockEngine = MockInferenceEngine(runtimeType: .mlx)
        mockEngine.isLoaded = true
        let controller = ModelSessionController(
            engine: mockEngine,
            onStatusMessage: { _ in }
        )
        let result = controller.applySamplerSettingsInPlace()
        #expect(result == true, "MLX engine should handle sampler settings in-place")
    }

    @Test("LiteRT engine returns false — requires full reload for sampler changes")
    @MainActor
    func testApplySamplerInPlace_LiteRTEngine_ReturnsFalse() async throws {
        let mockEngine = MockInferenceEngine(runtimeType: .litertlm)
        mockEngine.isLoaded = true
        let controller = ModelSessionController(
            engine: mockEngine,
            onStatusMessage: { _ in }
        )
        let result = controller.applySamplerSettingsInPlace()
        #expect(result == false, "LiteRT engine should require a full reload")
    }

    @Test("Unloaded engine always returns false regardless of runtime type")
    @MainActor
    func testApplySamplerInPlace_EngineNotLoaded_ReturnsFalse() async throws {
        let mockEngine = MockInferenceEngine(runtimeType: .mlx)
        mockEngine.isLoaded = false
        let controller = ModelSessionController(
            engine: mockEngine,
            onStatusMessage: { _ in }
        )
        let result = controller.applySamplerSettingsInPlace()
        #expect(result == false, "Unloaded engine should not attempt in-place settings")
    }
}
