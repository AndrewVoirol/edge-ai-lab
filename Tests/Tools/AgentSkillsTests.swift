// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for agent skill tools (`WikipediaSkillTool` and `MapSkillTool`).
///
/// These tools are NOT registered in `ToolRegistry.defaultTools` —
/// they are agent-specific skills used via the skill system.
@Suite struct AgentSkillsTests {

    // MARK: - WikipediaSkillTool Identity

    @Test("WikipediaSkillTool name is wikipedia_search")
    func wikipediaToolName() {
        #expect(WikipediaSkillTool.name == "wikipedia_search")
    }

    @Test("WikipediaSkillTool description is non-empty")
    func wikipediaToolDescription() {
        #expect(!WikipediaSkillTool.description.isEmpty)
    }

    // MARK: - WikipediaSkillTool Empty Query

    @Test("WikipediaSkillTool with empty query returns error JSON")
    func wikipediaEmptyQueryReturnsError() async throws {
        var tool = WikipediaSkillTool()
        tool.query = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = parsed["error"] as? String
        #expect(error != nil)
        if let errorMessage = error {
            #expect(errorMessage.contains("Query cannot be empty"))
        }
    }

    // MARK: - MapSkillTool Identity

    @Test("MapSkillTool name is show_map")
    func mapToolName() {
        #expect(MapSkillTool.name == "show_map")
    }

    @Test("MapSkillTool description is non-empty")
    func mapToolDescription() {
        #expect(!MapSkillTool.description.isEmpty)
    }

    // MARK: - MapSkillTool Empty Query

    @Test("MapSkillTool with empty query returns error JSON")
    func mapEmptyQueryReturnsError() async throws {
        var tool = MapSkillTool()
        tool.query = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let error = parsed["error"] as? String
        #expect(error != nil)
    }

    // MARK: - MapSkillTool Coordinate Parsing

    @Test("MapSkillTool with valid coordinates returns latitude and longitude")
    func mapCoordinatesParsing() async throws {
        var tool = MapSkillTool()
        tool.query = "48.8584, 2.2945"
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = try #require(json.data(using: .utf8))
        let parsed = try #require(try? JSONSerialization.jsonObject(with: data) as? [String: Any])
        let latitude = parsed["latitude"] as? Double
        let longitude = parsed["longitude"] as? Double
        #expect(latitude != nil)
        #expect(longitude != nil)
        if let lat = latitude, let lon = longitude {
            #expect(abs(lat - 48.8584) < 0.001)
            #expect(abs(lon - 2.2945) < 0.001)
        }
    }
}
