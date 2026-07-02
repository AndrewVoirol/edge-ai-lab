// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `CameraTool`, which signals the UI layer to present a photo picker.
@Suite struct CameraToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is take_photo")
    func toolName() {
        #expect(CameraTool.name == "take_photo")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!CameraTool.description.isEmpty)
    }

    // MARK: - Registration

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("take_photo"))
    }

    // MARK: - JSON Structure

    @Test("Result contains status key")
    func resultContainsStatus() async throws {
        let tool = CameraTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let status = parsed["status"] as? String
        #expect(status != nil)
    }

    @Test("Result contains photo_picker_requested status")
    func resultContainsPhotoPickerRequested() async throws {
        let tool = CameraTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let status = parsed["status"] as? String
        #expect(status == "photo_picker_requested")
    }

    @Test("Result JSON is parseable")
    func resultIsParseable() async throws {
        let tool = CameraTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
    }
}
