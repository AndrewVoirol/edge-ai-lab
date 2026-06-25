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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Integration tests for inference engine cancel behavior.
///
/// Validates three cancellation scenarios using `MockInstrumentedEngine`:
/// 1. **Mid-stream cancel** — stream stops before all chunks are emitted.
/// 2. **Cancel before stream** — calling `cancelGeneration()` before starting
///    a stream is a harmless no-op.
/// 3. **Cancel after completion** — calling `cancelGeneration()` after the
///    stream has fully drained does not crash or produce errors.
@Suite("Cancel Behavior")
struct CancelBehaviorTests {

    // MARK: - Helpers

    /// Creates a `MockInstrumentedEngine` pre-configured for cancel testing.
    ///
    /// - Parameters:
    ///   - chunkCount: Number of response chunks to generate.
    ///   - chunkDelay: Delay between chunks (seconds).
    /// - Returns: A configured engine with `simulateCancelBehavior` enabled.
    private func makeEngine(chunkCount: Int = 20, chunkDelay: TimeInterval = 0.1) -> MockInstrumentedEngine {
        let engine = MockInstrumentedEngine()
        engine.simulateCancelBehavior = true
        engine.chunkDelay = chunkDelay
        engine.mockResponseChunks = (0..<chunkCount).map { "chunk_\($0) " }
        return engine
    }

    // MARK: - Tests

    /// Verifies that calling `cancelGeneration()` mid-stream stops chunk delivery early.
    ///
    /// The engine is configured with 20 chunks at 0.1 s intervals (≈ 2 s total).
    /// After collecting a few chunks we call `cancelGeneration()` and confirm
    /// the stream terminates with fewer chunks than the full set.
    @Test("Cancel mid-stream stops chunk delivery")
    func cancelMidStream() async throws {
        let engine = makeEngine(chunkCount: 20, chunkDelay: 0.1)

        var collected: [String] = []
        let stream = engine.sendMessageStream("Hello", enableThinking: false)

        // Consume the stream in a child task so we can cancel from outside.
        let collectTask = Task<[String], Error> {
            var buffer: [String] = []
            for try await chunk in stream {
                buffer.append(chunk)
            }
            return buffer
        }

        // Wait long enough for a few chunks to be emitted (≥ 3 × 0.1 s).
        try await Task.sleep(for: .milliseconds(350))

        // Signal cancellation — the mock will stop yielding on the next iteration.
        engine.cancelGeneration()

        // Allow the stream to notice the flag and finish.
        collected = try await collectTask.value

        #expect(collected.count > 0, "Should have received at least one chunk before cancel")
        #expect(collected.count < 20, "Stream should have stopped early; got \(collected.count) of 20 chunks")
        #expect(engine.sendMessageCallCount == 1, "sendMessageStream should have been called exactly once")
    }

    /// Verifies that calling `cancelGeneration()` *before* starting a stream is a no-op.
    ///
    /// Because `MockInstrumentedEngine` resets its internal cancel flag at the start
    /// of each `sendMessageStream` call, a pre-emptive cancel should have no effect
    /// on a subsequently started stream — all chunks should be delivered normally.
    @Test("Cancel before stream start is a no-op")
    func cancelBeforeStreamStart() async throws {
        let engine = makeEngine(chunkCount: 5, chunkDelay: 0)

        // Cancel before any stream exists — should be harmless.
        engine.cancelGeneration()

        var collected: [String] = []
        for try await chunk in engine.sendMessageStream("Hello", enableThinking: false) {
            collected.append(chunk)
        }

        #expect(collected.count == 5, "All chunks should be delivered; cancel before stream is a no-op")
        #expect(engine.sendMessageCallCount == 1)
    }

    /// Verifies that calling `cancelGeneration()` after the stream has fully
    /// completed does not crash, throw, or otherwise produce side effects.
    @Test("Cancel after stream completion is a safe no-op")
    func cancelAfterCompletion() async throws {
        let engine = makeEngine(chunkCount: 4, chunkDelay: 0)

        var collected: [String] = []
        for try await chunk in engine.sendMessageStream("Hello", enableThinking: false) {
            collected.append(chunk)
        }

        // All chunks consumed — stream is finished.
        #expect(collected.count == 4, "All chunks should have been delivered")

        // Post-completion cancel must not crash or throw.
        engine.cancelGeneration()

        // Engine should still be in a usable state afterward.
        #expect(engine.sendMessageCallCount == 1)

        // Start another stream to prove the engine isn't wedged.
        var secondRun: [String] = []
        for try await chunk in engine.sendMessageStream("Follow-up", enableThinking: false) {
            secondRun.append(chunk)
        }

        #expect(secondRun.count == 4, "Second stream should deliver all chunks normally")
        #expect(engine.sendMessageCallCount == 2)
    }
}
