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

import XCTest
@testable import GemmaEdgeGallery_macOS

final class MultiTurnIntegrationTests: XCTestCase {
    var engine: InstrumentedEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = InstrumentedEngine()
    }

    override func tearDown() async throws {
        await engine.shutdown()
        engine = nil
        try await super.tearDown()
    }

    func testMultiTurnInference() async throws {
        // Find E4B model in the models/ directory
        let sourceFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let modelPath = projectRoot.appendingPathComponent("models/gemma-4-E4B-it.litertlm").path
        
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw XCTSkip("E4B model not found at \(modelPath). Skipping test.")
        }

        print("🚀 Initializing engine...")
        let flags = ExperimentalFlagsState(enableBenchmark: true, enableSpeculativeDecoding: nil, enableConversationConstrainedDecoding: false, visualTokenBudget: nil)
        
        try await engine.initialize(
            modelPath: modelPath,
            useGPU: true,
            cacheDir: NSTemporaryDirectory(),
            flags: flags,
            samplerConfig: nil
        )

        XCTAssertTrue(engine.isReady, "Engine should be ready")

        print("🚀 Sending turn 1...")
        var response1 = ""
        for try await chunk in engine.sendMessageStream("Hi, what is your name?") {
            response1 += chunk
            print(chunk, terminator: "")
        }
        print("\n✅ Turn 1 finished. Response: \(response1.count) chars")

        print("🚀 Sending turn 2...")
        var response2 = ""
        do {
            for try await chunk in engine.sendMessageStream("Can you repeat what I just asked?") {
                response2 += chunk
                print(chunk, terminator: "")
            }
            print("\n✅ Turn 2 finished. Response: \(response2.count) chars")
        } catch {
            print("\n❌ Turn 2 failed with error: \(error)")
            XCTFail("Turn 2 failed: \(error)")
        }
    }
}
