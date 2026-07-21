// Diagnostic test: Directly exercises MLXEngineAdapter with the on-disk model.
// Requires a local model directory — skips gracefully on CI or machines without the model.
// Run: xcodebuild test -workspace EdgeAILab.xcworkspace -scheme "Edge AI Lab" -destination 'platform=macOS' -only-testing "EdgeAILab_macOSTests/MLXDiagnosticTest" 2>&1

#if os(macOS)
@testable import EdgeAILab_macOS

import Testing
import Foundation
import Metal

/// Module-level precondition: Metal GPU available AND local model directory exists.
/// Defined outside MLXDiagnosticTest to avoid circular reference in @Suite macro.
private let mlxDiagnosticIsRunnable: Bool = {
    guard MTLCreateSystemDefaultDevice() != nil else { return false }
    let candidates = [
        NSString(string: #filePath)
            .deletingLastPathComponent  // Tests/Engine/
            .appending("/../../models/mlx-community--gemma-4-E2B-it-4bit"),
        NSHomeDirectory() + "/Antigravity/Projects/edge-ai-lab/models/mlx-community--gemma-4-E2B-it-4bit"
    ]
    let modelPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
        ?? candidates.last!
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: modelPath, isDirectory: &isDir)
    return exists && isDir.boolValue
}()

@Suite("MLX Diagnostic", .enabled(if: mlxDiagnosticIsRunnable, "Requires Metal GPU and local MLX model"))
struct MLXDiagnosticTest {

    /// Path to a locally-downloaded MLX model. Tests skip if this directory doesn't exist.
    nonisolated static let modelPath: String = {
        // Check the project-local models/ directory first, then the user's home cache.
        let candidates = [
            NSString(string: #filePath)
                .deletingLastPathComponent  // Tests/Engine/
                .appending("/../../models/mlx-community--gemma-4-E2B-it-4bit"),
            NSHomeDirectory() + "/Antigravity/Projects/edge-ai-lab/models/mlx-community--gemma-4-E2B-it-4bit"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? candidates.last!
    }()

    /// Generation WITHOUT system message — should produce clean response.
    @Test("MLX generates without system message")
    func testWithoutSystemMessage() async throws {

        let engine = MLXEngineAdapter()
        let config = ModelLoadConfig(
            modelPath: Self.modelPath,
            preferGPU: true,
            systemMessage: nil,
            supportsVision: true,
            supportsAudio: false,
            generationConfig: GenerationConfig(
                maxTokens: 50,
                temperature: 0.7,
                topP: 0.9,
                topK: 40
            )
        )

        try await engine.loadModel(config: config)

        var output = ""
        var tokenCount = 0
        let genConfig = GenerationConfig(maxTokens: 50, temperature: 0.7, topP: 0.9, topK: 40)
        for try await event in engine.generateStream(prompt: "What is 2+2? Answer briefly.", config: genConfig) {
            if case .text(let text) = event {
                output += text
                tokenCount += 1
            }
        }

        print("🧪 [NO SYSTEM] tokens=\(tokenCount), output: \(output.prefix(200))")
        #expect(tokenCount > 0, "Should generate at least 1 token")

        // Without a system message containing <|think|>, output should NOT contain channel markers.
        let hasChannelMarker = output.contains("<|channel>")
        print("🧪 [NO SYSTEM] contains channel marker: \(hasChannelMarker)")

        await engine.shutdown()
    }

    /// Generation WITH thinking token in system message — ThinkingParser separates thinking/response.
    @Test("MLX generates with thinking trigger and parser separates output")
    func testThinkingParserSeparation() async throws {

        let engine = MLXEngineAdapter()
        let config = ModelLoadConfig(
            modelPath: Self.modelPath,
            preferGPU: true,
            systemMessage: "<|think|>",
            supportsVision: true,
            supportsAudio: false,
            generationConfig: GenerationConfig(
                maxTokens: 200,
                temperature: 0.7,
                topP: 0.9,
                topK: 40
            )
        )

        try await engine.loadModel(config: config)

        var output = ""
        var tokenCount = 0
        let genConfig = GenerationConfig(maxTokens: 200, temperature: 0.7, topP: 0.9, topK: 40)
        for try await event in engine.generateStream(prompt: "What is 2+2? Answer briefly.", config: genConfig) {
            if case .text(let text) = event {
                output += text
                tokenCount += 1
            }
        }

        print("🧪 [THINKING] tokens=\(tokenCount)")

        // Parse with ThinkingParser — channel markers should be recognized
        var parser = ThinkingParser()
        let segments = parser.feed(output)
        let finalSegments = parser.finalize()
        let allSegments = segments + finalSegments

        var thinkingText = ""
        var responseText = ""
        for seg in allSegments {
            switch seg {
            case .thinking(let t): thinkingText += t
            case .response(let t): responseText += t
            }
        }

        print("🧪 [THINKING] thinking chars=\(thinkingText.count), response chars=\(responseText.count)")
        print("🧪 [THINKING] thinking prefix: \(thinkingText.prefix(100))")
        print("🧪 [THINKING] response prefix: \(responseText.prefix(100))")

        #expect(tokenCount > 0, "Should generate at least 1 token")

        // The parser should have classified SOME content as thinking (channel markers detected).
        // Response text should NOT contain raw channel markers.
        let responseHasMarkers = responseText.contains("<|channel>") || responseText.contains("<channel|>")
        print("🧪 [THINKING] response contains raw channel markers: \(responseHasMarkers)")
        #expect(!responseHasMarkers, "Response text should not contain raw channel markers after parsing")

        await engine.shutdown()
    }

    /// Settings take effect — temperature 0 should produce deterministic output.
    @Test("MLX settings apply correctly")
    func testSettingsApply() async throws {

        let engine = MLXEngineAdapter()
        let config = ModelLoadConfig(
            modelPath: Self.modelPath,
            preferGPU: true,
            systemMessage: nil,
            supportsVision: true,
            supportsAudio: false,
            generationConfig: GenerationConfig(
                maxTokens: 30,
                temperature: 0.0,
                topP: 1.0,
                topK: 1
            )
        )

        try await engine.loadModel(config: config)

        // Generate twice with temperature=0 (greedy) — should be identical
        var output1 = ""
        var output2 = ""
        let greedyConfig = GenerationConfig(maxTokens: 30, temperature: 0.0, topP: 1.0, topK: 1)

        for try await event in engine.generateStream(prompt: "What is the capital of France?", config: greedyConfig) {
            if case .text(let text) = event { output1 += text }
        }
        for try await event in engine.generateStream(prompt: "What is the capital of France?", config: greedyConfig) {
            if case .text(let text) = event { output2 += text }
        }

        print("🧪 [SETTINGS] Run 1: \(output1.prefix(100))")
        print("🧪 [SETTINGS] Run 2: \(output2.prefix(100))")
        print("🧪 [SETTINGS] Greedy match: \(output1 == output2)")

        #expect(!output1.isEmpty, "Greedy generation should produce output")
        #expect(output1 == output2, "Greedy (temp=0) generation should be deterministic")

        await engine.shutdown()
    }
}
#endif
