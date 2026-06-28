// Copyright 2026 Andrew Voirol. Apache-2.0
// Copyright 2026 Andrew Voirol
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `SensorsTool`, which returns environmental sensor data.
///
/// On macOS, the tool returns a graceful degradation error (sensors not available).
/// On iOS, actual sensor data requires physical hardware.
@Suite struct SensorsToolTests {

    // MARK: - Tool Identity

    @Test("Tool name is get_sensors")
    func toolName() {
        #expect(SensorsTool.name == "get_sensors")
    }

    @Test("Tool description is non-empty")
    func toolDescription() {
        #expect(!SensorsTool.description.isEmpty)
    }

    @Test("Tool is registered in ToolRegistry")
    func registeredInRegistry() {
        let toolNames = ToolRegistry.defaultTools.map { type(of: $0).name }
        #expect(toolNames.contains("get_sensors"))
    }

    // MARK: - macOS Graceful Degradation

    #if os(macOS)
    @Test("macOS returns error JSON with proper structure")
    func macOSReturnsError() async throws {
        let tool = SensorsTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Sensors not available on macOS"))
        #expect(json.contains("platform"))
        #expect(json.contains("macOS"))
    }

    @Test("macOS error JSON is parseable")
    func macOSErrorIsParseable() async throws {
        let tool = SensorsTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        let data = json.data(using: .utf8)!
        let rawParsed = try? JSONSerialization.jsonObject(with: data)
        let parsed = rawParsed as? [String: Any]
        #expect(parsed != nil)
        let platform = parsed?["platform"] as? String
        #expect(platform == "macOS")
    }
    #endif

    // MARK: - iOS Structure (compile-time only on macOS)

    #if os(iOS)
    @Test("iOS returns JSON with platform key")
    func iOSReturnsPlatform() async throws {
        let tool = SensorsTool()
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("platform"))
        #expect(json.contains("iOS"))
    }
    #endif
}
