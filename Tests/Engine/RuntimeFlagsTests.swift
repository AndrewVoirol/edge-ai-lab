// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("RuntimeFlags")
struct RuntimeFlagsTests {

    // MARK: - Construction

    @Test("default init has sensible defaults")
    func defaultInit() {
        let flags = RuntimeFlags()
        #expect(flags.enableBenchmark == false)
        #expect(flags.enableThinking == true)
        #expect(flags.enableSpeculativeDecoding == nil)
        #expect(flags.enableConversationConstrainedDecoding == false)
        #expect(flags.metalCacheLimit == nil)
        #expect(flags.metalMemoryLimit == nil)
        #expect(flags.maxImageResolution == nil)
        #expect(flags.maxImageTokenBudget == nil)
        #expect(flags.visualTokenBudget == nil)
    }

    @Test("custom init preserves all fields")
    func customInit() {
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 4096,
            metalMemoryLimit: 1024 * 1024 * 1024,
            metalCacheLimit: 256 * 1024 * 1024,
            maxImageResolution: 512,
            maxImageTokenBudget: 2048
        )
        #expect(flags.enableBenchmark == true)
        #expect(flags.enableThinking == true)
        #expect(flags.enableSpeculativeDecoding == true)
        #expect(flags.enableConversationConstrainedDecoding == true)
        #expect(flags.visualTokenBudget == 4096)
        #expect(flags.metalMemoryLimit == 1024 * 1024 * 1024)
        #expect(flags.metalCacheLimit == 256 * 1024 * 1024)
        #expect(flags.maxImageResolution == 512)
        #expect(flags.maxImageTokenBudget == 2048)
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = RuntimeFlags(
            enableBenchmark: true,
            enableThinking: true,
            enableSpeculativeDecoding: false,
            enableConversationConstrainedDecoding: true,
            visualTokenBudget: 8192,
            metalMemoryLimit: 2 * 1024 * 1024 * 1024,
            metalCacheLimit: 512 * 1024 * 1024,
            maxImageResolution: 768,
            maxImageTokenBudget: 4096
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuntimeFlags.self, from: data)
        #expect(decoded == original)
    }

    @Test("backward-compatible JSON decodes cleanly (no MLX-specific fields)")
    func backwardCompatibleJSON() throws {
        // Simulate old ExperimentalFlagsState JSON without MLX fields
        let json = """
        {
            "enableBenchmark": true,
            "enableSpeculativeDecoding": false,
            "enableConversationConstrainedDecoding": true
        }
        """.data(using: .utf8)!

        let flags = try JSONDecoder().decode(RuntimeFlags.self, from: json)
        #expect(flags.enableBenchmark == true)
        #expect(flags.enableSpeculativeDecoding == false)
        #expect(flags.enableConversationConstrainedDecoding == true)
        // MLX fields default to nil when missing
        #expect(flags.metalCacheLimit == nil)
        #expect(flags.metalMemoryLimit == nil)
        #expect(flags.maxImageResolution == nil)
        #expect(flags.maxImageTokenBudget == nil)
        #expect(flags.visualTokenBudget == nil)
    }

    // MARK: - LiteRT Conversion

    @Test("toLiteRTFlags preserves common fields")
    func toLiteRTFlags() {
        let flags = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: false,
            enableConversationConstrainedDecoding: true
        )
        let liteRTFlags = flags.toLiteRTFlags()
        #expect(liteRTFlags.enableBenchmark == true)
        #expect(liteRTFlags.enableSpeculativeDecoding == false)
        #expect(liteRTFlags.enableConversationConstrainedDecoding == true)
    }

    @Test("init from LiteRT flags preserves common fields")
    func initFromLiteRTFlags() {
        let liteRTFlags = ExperimentalFlagsState(
            enableBenchmark: true,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false,
            visualTokenBudget: nil
        )
        let flags = RuntimeFlags(from: liteRTFlags)
        #expect(flags.enableBenchmark == true)
        #expect(flags.enableSpeculativeDecoding == nil)
        #expect(flags.enableConversationConstrainedDecoding == false)
        // MLX fields should be nil when converted from LiteRT
        #expect(flags.metalCacheLimit == nil)
        #expect(flags.metalMemoryLimit == nil)
    }

    @Test("round-trip through LiteRT preserves common fields")
    func roundTripThroughLiteRT() {
        let original = RuntimeFlags(
            enableBenchmark: true,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true,
            metalCacheLimit: 256 * 1024 * 1024  // MLX-specific
        )
        let liteRT = original.toLiteRTFlags()
        let roundTripped = RuntimeFlags(from: liteRT)

        // Common fields preserved
        #expect(roundTripped.enableBenchmark == original.enableBenchmark)
        #expect(roundTripped.enableSpeculativeDecoding == original.enableSpeculativeDecoding)

        // MLX-specific fields lost (expected — LiteRT doesn't carry them)
        #expect(roundTripped.metalCacheLimit == nil)
    }

    // MARK: - Equatable

    @Test("Equatable works correctly")
    func equatable() {
        let a = RuntimeFlags(enableBenchmark: true, enableThinking: true)
        let b = RuntimeFlags(enableBenchmark: true, enableThinking: true)
        let c = RuntimeFlags(enableBenchmark: false, enableThinking: true)
        #expect(a == b)
        #expect(a != c)
    }
}
