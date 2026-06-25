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
import LiteRTLM

// MARK: - UnitConverterTool

/// Converts values between common unit types using Foundation's `Measurement` API
/// for guaranteed accuracy.
///
/// Supported categories:
/// - **Temperature**: celsius, fahrenheit, kelvin
/// - **Distance**: meters, kilometers, miles, feet, inches, yards
/// - **Weight**: kilograms (kg), pounds (lbs), ounces (oz), grams
/// - **Data**: bytes, kilobytes (kb), megabytes (mb), gigabytes (gb), terabytes (tb)
///
/// Example: `convert_units(value: 100, fromUnit: "celsius", toUnit: "fahrenheit")` → 212°F
struct UnitConverterTool: Tool {
    static let name = "convert_units"
    static let description = "Convert a value between units. Supports temperature, distance, weight, and data units."

    @ToolParam(description: "The numeric value to convert")
    var value: Double

    @ToolParam(description: "The source unit (e.g. 'celsius', 'meters', 'kg', 'mb')")
    var fromUnit: String

    @ToolParam(description: "The target unit (e.g. 'fahrenheit', 'miles', 'lbs', 'gb')")
    var toUnit: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = [
            "value": value,
            "fromUnit": fromUnit,
            "toUnit": toUnit
        ]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }
        let from = fromUnit.lowercased().trimmingCharacters(in: .whitespaces)
        let to = toUnit.lowercased().trimmingCharacters(in: .whitespaces)

        // Attempt to resolve both units to the same dimension
        guard let sourceDimUnit = Self.resolveUnit(from),
              let targetDimUnit = Self.resolveUnit(to) else {
            resultString = jsonString(from: [
                "error": "Unknown unit. Supported units: celsius, fahrenheit, kelvin, meters, kilometers, miles, feet, inches, yards, kg, lbs, oz, grams, bytes, kb, mb, gb, tb",
                "from_unit": fromUnit,
                "to_unit": toUnit
            ])
            return resultString
        }

        // Verify units are in the same dimension by attempting conversion
        // Foundation Measurement handles cross-dimension errors
                guard type(of: sourceDimUnit) == type(of: targetDimUnit) else {
            resultString = jsonString(from: [
                "error": "Cannot convert between different unit types (e.g. temperature to distance)",
                "from_unit": fromUnit,
                "to_unit": toUnit
            ])
            return resultString
        }

        let sourceMeasurement = Measurement(value: value, unit: sourceDimUnit)
        let converted = sourceMeasurement.converted(to: targetDimUnit)

        let formatted: String
        if converted.value == converted.value.rounded() &&
            !converted.value.isInfinite && !converted.value.isNaN &&
            abs(converted.value) < 1e15 {
            formatted = String(format: "%.0f", converted.value)
        } else {
            formatted = String(format: "%.6g", converted.value)
        }

        resultString = jsonString(from: [
            "original_value": value,
            "original_unit": fromUnit,
            "converted_value": converted.value,
            "converted_unit": toUnit,
            "formatted_result": "\(formatted) \(toUnit)"
        ])
        return resultString
    }

    // MARK: Unit Resolution

    /// Resolves a user-friendly unit name to a Foundation `Dimension` subclass instance.
    /// Returns nil for unrecognized units.
    private static func resolveUnit(_ name: String) -> Dimension? {
        switch name {
        // Temperature
        case "celsius", "c":
            return UnitTemperature.celsius
        case "fahrenheit", "f":
            return UnitTemperature.fahrenheit
        case "kelvin", "k":
            return UnitTemperature.kelvin

        // Distance
        case "meters", "meter", "m":
            return UnitLength.meters
        case "kilometers", "kilometer", "km":
            return UnitLength.kilometers
        case "miles", "mile", "mi":
            return UnitLength.miles
        case "feet", "foot", "ft":
            return UnitLength.feet
        case "inches", "inch", "in":
            return UnitLength.inches
        case "yards", "yard", "yd":
            return UnitLength.yards

        // Weight / Mass
        case "kilograms", "kilogram", "kg":
            return UnitMass.kilograms
        case "pounds", "pound", "lbs", "lb":
            return UnitMass.pounds
        case "ounces", "ounce", "oz":
            return UnitMass.ounces
        case "grams", "gram", "g":
            return UnitMass.grams

        // Data Storage
        case "bytes", "byte", "b":
            return UnitInformationStorage.bytes
        case "kilobytes", "kilobyte", "kb":
            return UnitInformationStorage.kilobytes
        case "megabytes", "megabyte", "mb":
            return UnitInformationStorage.megabytes
        case "gigabytes", "gigabyte", "gb":
            return UnitInformationStorage.gigabytes
        case "terabytes", "terabyte", "tb":
            return UnitInformationStorage.terabytes

        default:
            return nil
        }
    }
}
