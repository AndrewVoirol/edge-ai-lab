// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - MotionTool Tests

/// Tests for the MotionTool's structural behavior and platform-specific degradation.
@Suite("MotionTool")
struct MotionToolTests {

    @Test("Tool name is get_device_motion")
    func toolName() {
        #expect(MotionTool.name == "get_device_motion")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!MotionTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_device_motion"))
    }

    #if os(macOS)
    @Test("macOS returns error JSON (no motion hardware)")
    func macOSGracefulDegradation() async throws {
        let tool = MotionTool()
        let result = try await tool.run()
        let resultString = result as! String
        #expect(resultString.contains("error"))
        #expect(resultString.contains("not available on macOS"))
    }
    #endif
}
