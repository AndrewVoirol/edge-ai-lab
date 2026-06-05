import XCTest
import LiteRTLM
import CoreLocation

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

final class MCPClientTests: XCTestCase {

    // MARK: - MCPServerConfig Tests

    func testMCPServerConfigInitialization() {
        let config = MCPServerConfig(
            name: "Test Server",
            enabled: true,
            command: "/usr/bin/node",
            args: ["test.js"],
            env: ["KEY": "VALUE"]
        )

        XCTAssertEqual(config.name, "Test Server")
        XCTAssertTrue(config.enabled)
        XCTAssertEqual(config.command, "/usr/bin/node")
        XCTAssertEqual(config.args, ["test.js"])
        XCTAssertEqual(config.env, ["KEY": "VALUE"])
        XCTAssertNotNil(config.id)
    }

    func testMCPServerStorageSaveAndLoad() {
        let originalConfigs = [
            MCPServerConfig(name: "S1", enabled: true, command: "c1"),
            MCPServerConfig(name: "S2", enabled: false, command: "c2")
        ]

        MCPServerStorage.save(originalConfigs)
        let loadedConfigs = MCPServerStorage.load()

        XCTAssertEqual(loadedConfigs.count, 2)
        XCTAssertEqual(loadedConfigs[0].name, "S1")
        XCTAssertTrue(loadedConfigs[0].enabled)
        XCTAssertEqual(loadedConfigs[1].name, "S2")
        XCTAssertFalse(loadedConfigs[1].enabled)
    }

    // MARK: - MCPClient Stub Tests

    func testMCPClientInitialization() {
        let config = MCPServerConfig(name: "S", command: "c")
        let client = MCPClient(config: config)

        XCTAssertEqual(client.config.name, "S")
        XCTAssertEqual(client.state, .stopped)
    }

    func testMCPClientIOSStub() async {
        #if os(iOS)
        let config = MCPServerConfig(name: "S", command: "c")
        let client = MCPClient(config: config)

        await client.start()

        if case .failed(let error) = client.state {
            XCTAssertTrue(error.contains("not supported on iOS"))
        } else {
            XCTFail("MCP Client should fail on iOS")
        }
        #endif
    }

    // MARK: - DynamicMCPBridge Tests

    func testMCPBridgeManagerRegistration() {
        let manager = MCPBridgeManager.shared
        manager.clear()

        let config = MCPServerConfig(name: "TestClient", command: "test")
        let client = MCPClient(config: config)

        let mockTools = [
            MCPToolInfo(name: "mock_tool_1", description: "First mock tool", inputSchema: [:]),
            MCPToolInfo(name: "mock_tool_2", description: "Second mock tool", inputSchema: [:])
        ]

        let bridged = manager.bridge(tools: mockTools, client: client)

        XCTAssertEqual(bridged.count, 2)
        XCTAssertEqual(type(of: bridged[0]).name, "mock_tool_1")
        XCTAssertEqual(type(of: bridged[1]).name, "mock_tool_2")
    }

    func testMCPBridgePoolExhaustion() {
        let manager = MCPBridgeManager.shared
        manager.clear()

        let config = MCPServerConfig(name: "TestClient", command: "test")
        let client = MCPClient(config: config)

        // Create 12 tools (pool size is 10)
        var mockTools: [MCPToolInfo] = []
        for i in 1...12 {
            mockTools.append(MCPToolInfo(name: "tool_\(i)", description: "desc", inputSchema: [:]))
        }

        let bridged = manager.bridge(tools: mockTools, client: client)

        // Should cap out at 10 tools
        XCTAssertEqual(bridged.count, 10)
    }

    // MARK: - Agent Skills Tests

    func testWikipediaSkillToolValidation() async throws {
        var tool = WikipediaSkillTool()
        
        // Empty query validation
        tool.query = ""
        let emptyResult = try await tool.run() as! String
        XCTAssertTrue(emptyResult.contains("Query cannot be empty"))

        // Run query (Wikipedia open API might be offline, so we handle offline gracefully in tool. Let's make sure it returns a string response)
        tool.query = "Swift Programming Language"
        let result = try await tool.run() as! String
        XCTAssertTrue(result.contains("type"))
        XCTAssertTrue(result.contains("wikipedia"))
    }

    func testMapSkillToolCoordinatesParsing() async throws {
        var tool = MapSkillTool()
        
        // Empty query
        tool.query = ""
        let emptyResult = try await tool.run() as! String
        XCTAssertTrue(emptyResult.contains("Location query cannot be empty"))

        // Coordinate query parsing
        tool.query = "48.8584, 2.2945"
        let coordResult = try await tool.run() as! String
        XCTAssertTrue(coordResult.contains("latitude"))
        XCTAssertTrue(coordResult.contains("48.8584"))
        XCTAssertTrue(coordResult.contains("2.2945"))
        XCTAssertTrue(coordResult.contains("Coordinates"))
    }
}
