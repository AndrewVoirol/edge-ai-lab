// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `MotionTool`'s structural behavior and platform-specific degradation.
///
/// On macOS: motion hardware is absent, so `run()` returns an error JSON.
/// On iOS: only identity tests run — actual motion data requires physical hardware.
@Suite("MotionTool – Tools")
struct MotionToolSwiftTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_device_motion")
    func toolName() {
        #expect(MotionTool.name == "get_device_motion")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!MotionTool.description.isEmpty)
    }

    // MARK: - Registration

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_device_motion"))
    }

    // MARK: - macOS Graceful Degradation

    #if os(macOS)
    @Test("macOS returns error JSON with error key")
    func macOSReturnsErrorJSON() async throws {
        let tool = MotionTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = parsed["error"] as? String
        #expect(error != nil)
    }

    @Test("macOS error mentions not available on macOS")
    func macOSErrorMessage() async throws {
        let tool = MotionTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("not available on macOS"))
    }
    #endif
}
