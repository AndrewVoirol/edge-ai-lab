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

/// Tests for `DateTimeTool`, which returns current date/time information
/// with optional timezone support.
@Suite struct DateTimeToolTests {

    // MARK: - Default Timezone

    @Test("Default timezone (empty string) returns current timezone info")
    func defaultTimezoneReturnsCurrentInfo() async throws {
        var tool = DateTimeTool()
        tool.timezone = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        // Should contain the device's current timezone identifier
        // JSON may escape slashes (e.g., "America\/New_York"), so split on "/"
        // and check each component independently.
        let currentTZ = TimeZone.current.identifier
        let tzParts = currentTZ.split(separator: "/")
        for part in tzParts {
            #expect(json.contains(String(part)))
        }
        #expect(!json.contains("error"))
    }

    // MARK: - Known Timezone

    @Test("Known timezone 'America/New_York' appears in result")
    func knownTimezoneNewYork() async throws {
        var tool = DateTimeTool()
        tool.timezone = "America/New_York"
        let result = try await tool.run()
        let json = try #require(result as? String)
        // JSON may escape slashes, so check components independently
        #expect(json.contains("America"))
        #expect(json.contains("New_York"))
        #expect(!json.contains("error"))
    }

    @Test("Known timezone 'Asia/Tokyo' appears in result")
    func knownTimezoneTokyo() async throws {
        var tool = DateTimeTool()
        tool.timezone = "Asia/Tokyo"
        let result = try await tool.run()
        let json = try #require(result as? String)
        // JSON may escape slashes, so check components independently
        #expect(json.contains("Asia"))
        #expect(json.contains("Tokyo"))
        #expect(!json.contains("error"))
    }

    // MARK: - Invalid Timezone

    @Test("Invalid timezone returns JSON error about unknown timezone")
    func invalidTimezoneReturnsError() async throws {
        var tool = DateTimeTool()
        tool.timezone = "Invalid/FakeTimezone"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Unknown timezone"))
    }

    @Test("Another invalid timezone 'Mars/Olympus' returns error")
    func anotherInvalidTimezoneReturnsError() async throws {
        var tool = DateTimeTool()
        tool.timezone = "Mars/Olympus"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Unknown timezone"))
    }

    // MARK: - Expected JSON Keys

    @Test("Result contains all expected keys: date, time, timezone, utc_offset, day_of_week")
    func resultContainsExpectedKeys() async throws {
        var tool = DateTimeTool()
        tool.timezone = ""
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("\"date\""))
        #expect(json.contains("\"time\""))
        #expect(json.contains("\"timezone\""))
        #expect(json.contains("\"utc_offset\""))
        #expect(json.contains("\"day_of_week\""))
    }

    @Test("Result for specific timezone also contains unix_timestamp and is_dst")
    func resultContainsTimestampAndDST() async throws {
        var tool = DateTimeTool()
        tool.timezone = "Europe/London"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("\"unix_timestamp\""))
        #expect(json.contains("\"is_dst\""))
    }
}
