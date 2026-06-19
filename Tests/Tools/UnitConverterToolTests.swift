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

import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `UnitConverterTool`, which converts values between
/// temperature, distance, weight, and data storage units.
@Suite struct UnitConverterToolTests {

    // MARK: - Temperature Conversions

    @Test("100 celsius → fahrenheit contains 212")
    func celsiusToFahrenheit() async throws {
        var tool = UnitConverterTool()
        tool.value = 100.0
        tool.fromUnit = "celsius"
        tool.toUnit = "fahrenheit"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("212"))
        #expect(!json.contains("error"))
    }

    @Test("0 celsius → kelvin contains 273")
    func celsiusToKelvin() async throws {
        var tool = UnitConverterTool()
        tool.value = 0.0
        tool.fromUnit = "celsius"
        tool.toUnit = "kelvin"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("273"))
        #expect(!json.contains("error"))
    }

    @Test("32 fahrenheit → celsius contains 0")
    func fahrenheitToCelsius() async throws {
        var tool = UnitConverterTool()
        tool.value = 32.0
        tool.fromUnit = "fahrenheit"
        tool.toUnit = "celsius"
        let result = try await tool.run()
        let json = try #require(result as? String)
        // 32°F = 0°C
        #expect(json.contains("converted_value"))
        #expect(!json.contains("error"))
    }

    // MARK: - Distance Conversions

    @Test("1 mile → meters contains 1609")
    func milesToMeters() async throws {
        var tool = UnitConverterTool()
        tool.value = 1.0
        tool.fromUnit = "miles"
        tool.toUnit = "meters"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("1609"))
        #expect(!json.contains("error"))
    }

    @Test("1 kilometer → meters contains 1000")
    func kilometersToMeters() async throws {
        var tool = UnitConverterTool()
        tool.value = 1.0
        tool.fromUnit = "km"
        tool.toUnit = "meters"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("1000"))
        #expect(!json.contains("error"))
    }

    // MARK: - Weight Conversions

    @Test("1 kg → lbs contains 2.2")
    func kilogramsToLbs() async throws {
        var tool = UnitConverterTool()
        tool.value = 1.0
        tool.fromUnit = "kg"
        tool.toUnit = "lbs"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("2.2"))
        #expect(!json.contains("error"))
    }

    @Test("1 lb → grams contains 453")
    func lbsToGrams() async throws {
        var tool = UnitConverterTool()
        tool.value = 1.0
        tool.fromUnit = "lbs"
        tool.toUnit = "grams"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("453"))
        #expect(!json.contains("error"))
    }

    // MARK: - Data Storage Conversions

    @Test("1 gb → mb contains 1000")
    func gigabytesToMegabytes() async throws {
        var tool = UnitConverterTool()
        tool.value = 1.0
        tool.fromUnit = "gb"
        tool.toUnit = "mb"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("1000"))
        #expect(!json.contains("error"))
    }

    // MARK: - Error Cases

    @Test("Cross-dimension error: celsius → meters")
    func crossDimensionError() async throws {
        var tool = UnitConverterTool()
        tool.value = 100.0
        tool.fromUnit = "celsius"
        tool.toUnit = "meters"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Cannot convert"))
    }

    @Test("Unknown unit 'foobar' returns error")
    func unknownUnitReturnsError() async throws {
        var tool = UnitConverterTool()
        tool.value = 100.0
        tool.fromUnit = "foobar"
        tool.toUnit = "celsius"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Unknown unit"))
    }

    @Test("Unknown target unit 'quux' returns error")
    func unknownTargetUnitReturnsError() async throws {
        var tool = UnitConverterTool()
        tool.value = 50.0
        tool.fromUnit = "celsius"
        tool.toUnit = "quux"
        let result = try await tool.run()
        let json = try #require(result as? String)
        #expect(json.contains("error"))
        #expect(json.contains("Unknown unit"))
    }

    // MARK: - Case Aliases

    @Test("Alias 'kg' produces same result as 'kilograms'")
    func aliasKgSameAsKilograms() async throws {
        var toolShort = UnitConverterTool()
        toolShort.value = 5.0
        toolShort.fromUnit = "kg"
        toolShort.toUnit = "lbs"
        let resultShort = try await toolShort.run()
        let jsonShort = try #require(resultShort as? String)

        var toolLong = UnitConverterTool()
        toolLong.value = 5.0
        toolLong.fromUnit = "kilograms"
        toolLong.toUnit = "lbs"
        let resultLong = try await toolLong.run()
        let jsonLong = try #require(resultLong as? String)

        // Both should contain the same converted_value
        #expect(jsonShort.contains("converted_value"))
        #expect(jsonLong.contains("converted_value"))
        // Extract converted_value substring to compare numerically
        #expect(jsonShort.contains("11.02") || jsonShort.contains("11.0"))
        #expect(jsonLong.contains("11.02") || jsonLong.contains("11.0"))
    }
}
