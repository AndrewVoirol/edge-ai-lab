// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `SystemHealthTool`, which reports thermal state, memory, battery, and disk space.
@Suite struct SystemHealthToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_system_health")
    func toolName() {
        #expect(SystemHealthTool.name == "get_system_health")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!SystemHealthTool.description.isEmpty)
    }

    // MARK: - Registration

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_system_health"))
    }

    // MARK: - JSON Structure

    @Test("Result JSON contains all expected keys")
    func resultContainsExpectedKeys() async throws {
        let tool = SystemHealthTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(parsed["thermal_state"] != nil)
        #expect(parsed["available_memory_mb"] != nil)
        #expect(parsed["memory_pressure"] != nil)
        #expect(parsed["processor_count"] != nil)
        #expect(parsed["system_uptime"] != nil)
    }

    @Test("Available memory is a positive value")
    func availableMemoryIsPositive() async throws {
        let tool = SystemHealthTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let memoryString = parsed["available_memory_mb"] as? String
        #expect(memoryString != nil)
        if let memStr = memoryString, let memValue = Double(memStr) {
            #if targetEnvironment(simulator)
            // iOS Simulator may report 0 available memory
            #expect(memValue >= 0)
            #else
            #expect(memValue > 0)
            #endif
        }
    }

    @Test("Processor count is a positive number")
    func processorCountIsPositive() async throws {
        let tool = SystemHealthTool()
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

    @Test("Result JSON is parseable")
    func resultIsParseable() async throws {
        let tool = SystemHealthTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
    }

    // MARK: - macOS Battery Fields

    #if os(macOS)
    @Test("macOS battery fields report real DeviceMetrics values")
    func macOSBatteryFields() async throws {
        let tool = SystemHealthTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])

        // battery_level_percent is Int (MacBook) or "unavailable" (desktop Mac)
        let hasLevel = parsed["battery_level_percent"] != nil
        #expect(hasLevel)

        // battery_state is always a valid power source string
        let batteryState = parsed["battery_state"] as? String
        #expect(batteryState != nil)
        let validStates: Set<String> = ["ac", "battery", "charging", "full", "unknown"]
        #expect(validStates.contains(batteryState ?? ""))
    }
    #endif
}
