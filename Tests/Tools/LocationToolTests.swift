// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `LocationTool`'s structural behavior.
///
/// Note: `run()` is NOT called because it requires location permissions
/// which are unavailable in unit test environments.
@Suite("LocationTool – Tools")
struct LocationToolSwiftTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_location")
    func toolName() {
        #expect(LocationTool.name == "get_location")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!LocationTool.description.isEmpty)
    }

    // MARK: - Registration

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_location"))
    }
}
