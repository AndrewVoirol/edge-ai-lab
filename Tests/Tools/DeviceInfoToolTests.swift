// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `DeviceInfoTool`, which returns hardware and software information.
@Suite struct DeviceInfoToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_device_info")
    func toolName() {
        #expect(DeviceInfoTool.name == "get_device_info")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!DeviceInfoTool.description.isEmpty)
    }

    // MARK: - Registration

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_device_info"))
    }

    // MARK: - JSON Structure

    @Test("Result JSON contains all expected keys")
    func resultContainsExpectedKeys() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(parsed["device_model"] != nil)
        #expect(parsed["platform"] != nil)
        #expect(parsed["os_version"] != nil)
        #expect(parsed["processor_count"] != nil)
        #expect(parsed["physical_memory_gb"] != nil)
        #expect(parsed["thermal_state"] != nil)
    }

    @Test("Processor count is a positive number")
    func processorCountIsPositive() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let processorCount = parsed["processor_count"] as? Int
        #expect(processorCount != nil)
        if let count = processorCount {
            #expect(count > 0)
        }
    }

    #if os(macOS)
    @Test("Platform reports macOS on macOS")
    func platformIsMacOS() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let platform = parsed["platform"] as? String
        #expect(platform == "macOS")
    }
    #endif

    #if os(iOS)
    @Test("Platform reports iOS on iOS")
    func platformIsIOS() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let platform = parsed["platform"] as? String
        #expect(platform == "iOS")
    }
    #endif

    @Test("Result JSON is parseable")
    func resultIsParseable() async throws {
        let tool = DeviceInfoTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
    }
}
