// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - LocationTool Tests

/// Tests for the LocationTool's structural behavior and error handling.
/// Note: Actual GPS functionality requires device hardware and cannot be unit-tested.
@Suite("LocationTool")
struct LocationToolTests {

    @Test("Tool name is get_location")
    func toolName() {
        #expect(LocationTool.name == "get_location")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!LocationTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_location"))
    }
}
