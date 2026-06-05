import Foundation
import LiteRTLM
#if os(iOS)
import UIKit
#endif

// MARK: - Tool Call Observability

/// Thread-safe tracker to intercept tool executions at runtime.
public final class ToolExecutionTracker: @unchecked Sendable {
    public static let shared = ToolExecutionTracker()
    
    private let lock = NSRecursiveLock()
    private var callback: ((ToolCallEvent) -> Void)?
    
    private init() {}
    
    /// Register a callback to be notified when a tool executes.
    public func registerCallback(_ callback: @escaping (ToolCallEvent) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.callback = callback
    }
    
    /// Remove the active callback.
    public func clearCallback() {
        lock.lock()
        defer { lock.unlock() }
        self.callback = nil
    }
    
    /// Notify the tracker that a tool was executed.
    public func notify(_ event: ToolCallEvent) {
        lock.lock()
        let activeCallback = self.callback
        lock.unlock()
        activeCallback?(event)
    }
}

public struct ToolCallEvent: Identifiable, Sendable {
    /// Unique identifier for this tool call event.
    public let id = UUID()

    /// The name of the tool that was invoked (e.g., "calculate", "get_device_info").
    public let toolName: String

    /// JSON-serialized string of the arguments passed to the tool.
    public let arguments: String

    /// JSON-serialized string of the tool's return value.
    public let result: String

    /// Wall-clock duration of the tool execution in milliseconds.
    public let durationMs: Double

    /// When this tool call occurred.
    public let timestamp: Date

    /// Whether the tool completed without throwing an error.
    public let succeeded: Bool

    public init(toolName: String, arguments: String, result: String, durationMs: Double, timestamp: Date, succeeded: Bool) {
        self.toolName = toolName
        self.arguments = arguments
        self.result = result
        self.durationMs = durationMs
        self.timestamp = timestamp
        self.succeeded = succeeded
    }
}

// MARK: - JSON Serialization Helper

/// Converts a dictionary to a pretty-printed JSON string.
/// Falls back to a debug description if serialization fails.
private func jsonString(from dictionary: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(
        withJSONObject: dictionary,
        options: [.prettyPrinted, .sortedKeys]
    ) else {
        return "{\"error\": \"Failed to serialize result\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{\"error\": \"Failed to encode result\"}"
}

// MARK: - CalculatorTool

/// Evaluates mathematical expressions safely using NSExpression.
///
/// Supports basic arithmetic (+, -, *, /), parentheses, and common math functions
/// available through NSExpression. Does **not** execute arbitrary code — NSExpression
/// is limited to a safe subset of operations.
///
/// Example prompts the model might generate:
/// - `calculate(expression: "2 + 3 * 4")` → 14
/// - `calculate(expression: "(100 - 32) * 5 / 9")` → 37.78
struct CalculatorTool: Tool {
    static let name = "calculate"
    static let description = "Evaluate a mathematical expression safely and return the result"

    @ToolParam(description: "The mathematical expression to evaluate, e.g. '2 + 3 * 4'")
    var expression: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["expression": expression]
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
                let regex = try! NSRegularExpression(pattern: "(?<!\\.)\\b(\\d+)\\b(?!\\.)")
        let doubleExpression = regex.stringByReplacingMatches(in: expression, range: NSRange(expression.startIndex..., in: expression), withTemplate: "$1.0")
        let nsExpression = NSExpression(format: doubleExpression)
        guard let result = nsExpression.expressionValue(with: nil, context: nil) as? NSNumber else {
            resultString = jsonString(from: [
                "error": "Expression did not evaluate to a number",
                "expression": expression
            ])
            return resultString
        }

        let doubleResult = result.doubleValue
        // Format nicely: strip trailing .0 for integer results
        let formatted: String
        if doubleResult == doubleResult.rounded() && !doubleResult.isInfinite && !doubleResult.isNaN {
            formatted = String(format: "%.0f", doubleResult)
        } else {
            formatted = String(format: "%.6g", doubleResult)
        }

        resultString = jsonString(from: [
            "expression": expression,
            "result": doubleResult,
            "formatted_result": formatted
        ])
        return resultString
    }
}

// MARK: - DateTimeTool

/// Returns the current date, time, and timezone information.
///
/// Optionally accepts an IANA timezone identifier to report the time in a
/// different timezone. Defaults to the device's current timezone.
///
/// Example prompts:
/// - `get_current_datetime()` → current local time
/// - `get_current_datetime(timezone: "Asia/Tokyo")` → current time in Tokyo
struct DateTimeTool: Tool {
    static let name = "get_current_datetime"
    static let description = "Get the current date, time, and timezone information"

    @ToolParam(description: "IANA timezone identifier, e.g. 'America/New_York'. Defaults to device timezone.")
    var timezone: String = ""

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["timezone": timezone]
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
        let now = Date()
        let tz: TimeZone
        if !timezone.isEmpty, let requested = TimeZone(identifier: timezone) {
            tz = requested
        } else if !timezone.isEmpty {
            resultString = jsonString(from: [
                "error": "Unknown timezone identifier: '\(timezone)'",
                "available_example": "America/New_York, Europe/London, Asia/Tokyo"
            ])
            return resultString
        } else {
            tz = TimeZone.current
        }


        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = tz
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "HH:mm:ss"
        let timeString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "EEEE"
        let dayOfWeek = dateFormatter.string(from: now)

        let offsetSeconds = tz.secondsFromGMT(for: now)
                let sign = offsetSeconds < 0 ? "-" : "+"
        let absSeconds = abs(offsetSeconds)
        let offsetHours = absSeconds / 3600
        let offsetMinutes = (absSeconds % 3600) / 60
        let utcOffset = String(format: "%@%02d:%02d", sign, offsetHours, offsetMinutes)

        resultString = jsonString(from: [
            "date": dateString,
            "time": timeString,
            "timezone": tz.identifier,
            "utc_offset": utcOffset,
            "unix_timestamp": now.timeIntervalSince1970,
            "day_of_week": dayOfWeek,
            "is_dst": tz.isDaylightSavingTime(for: now)
        ])
        return resultString
    }
}

// MARK: - DeviceInfoTool

/// Returns hardware and software information about the device running the model.
///
/// Uses the project's `DeviceMetrics` utility for consistent thermal and memory
/// reporting. This tool lets the model understand its execution environment.
struct DeviceInfoTool: Tool {
    static let name = "get_device_info"
    static let description = "Get device hardware and software information including model, OS version, processor, memory, and thermal state"

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = [:]
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
        let thermalLevel = DeviceMetrics.currentThermalLevel
        let availableMemory = DeviceMetrics.formattedAvailableMemory

        let platform: String
        let osVersion: String
        #if os(iOS)
        platform = "iOS"
        osVersion = await UIDevice.current.systemVersion
        #elseif os(macOS)
        platform = "macOS"
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #else
        platform = "unknown"
        osVersion = "unknown"
        #endif

        let processorCount = ProcessInfo.processInfo.processorCount
        let activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        resultString = jsonString(from: [
            "device_model": DeviceMetrics.deviceModel,
            "platform": platform,
            "os_version": osVersion,
            "processor_count": processorCount,
            "active_processor_count": activeProcessorCount,
            "physical_memory_gb": String(format: "%.1f", physicalMemoryGB),
            "available_memory": availableMemory,
            "thermal_state": thermalLevel.label,
            "thermal_symbol": thermalLevel.symbolName
        ])
        return resultString
    }
}

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

// MARK: - TextAnalyzerTool

/// Analyzes text properties including word count, character count, sentence count,
/// paragraph count, average word length, reading time estimate, and detected language.
///
/// Uses `NLLanguageRecognizer` for language detection and word-per-minute estimates
/// for reading time (250 WPM average adult reading speed).
///
/// Example: `analyze_text(text: "Hello world. This is a test.")` → word count, stats, etc.
struct TextAnalyzerTool: Tool {
    static let name = "analyze_text"
    static let description = "Analyze text properties including word count, character count, sentence count, reading time, and detected language"

    @ToolParam(description: "The text to analyze")
    var text: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["text": text]
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
        // Word count — split on whitespace and newlines, filter empties
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        let wordCount = words.count

        // Character counts
        let characterCount = text.count
        let characterCountNoSpaces = text.filter { !$0.isWhitespace }.count

        // Sentence count — use linguistic tagger for accuracy
        var sentenceCount = 0
        text.enumerateSubstrings(
            in: text.startIndex...,
            options: [.bySentences, .localized]
        ) { _, _, _, _ in
            sentenceCount += 1
        }
        // Fallback: at least 1 sentence if there's text
        if sentenceCount == 0 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sentenceCount = 1
        }

        // Paragraph count — split by double newlines or single newlines
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let paragraphCount = max(paragraphs.count, text.isEmpty ? 0 : 1)

        // Average word length
        let totalCharacters = words.reduce(0) { $0 + $1.count }
        let averageWordLength = wordCount > 0
            ? Double(totalCharacters) / Double(wordCount)
            : 0.0

        // Reading time estimate (250 words per minute average)
        let readingTimeMinutes = Double(wordCount) / 250.0
        let readingTimeFormatted: String
        if readingTimeMinutes < 1.0 {
            let seconds = Int(readingTimeMinutes * 60)
            readingTimeFormatted = "\(max(seconds, 1)) seconds"
        } else {
            readingTimeFormatted = String(format: "%.1f minutes", readingTimeMinutes)
        }

        // Language detection using NLLanguageRecognizer
        let detectedLanguage: String
        if #available(iOS 12.0, macOS 10.14, *) {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage {
                detectedLanguage = Locale.current.localizedString(
                    forLanguageCode: language.rawValue
                ) ?? language.rawValue
            } else {
                detectedLanguage = "undetermined"
            }
        } else {
            detectedLanguage = "unavailable"
        }

        resultString = jsonString(from: [
            "word_count": wordCount,
            "character_count": characterCount,
            "character_count_no_spaces": characterCountNoSpaces,
            "sentence_count": sentenceCount,
            "paragraph_count": paragraphCount,
            "average_word_length": String(format: "%.1f", averageWordLength),
            "estimated_reading_time": readingTimeFormatted,
            "detected_language": detectedLanguage
        ])
        return resultString
    }
}

// MARK: - NLLanguageRecognizer Import

import NaturalLanguage

// MARK: - SystemHealthTool

/// Introspects the model's own runtime environment — thermal state, memory pressure,
/// battery level, and disk space.
///
/// This is the **killer differentiator** for on-device function calling: the model
/// can reason about its own hardware constraints. For example:
/// - "Am I running hot? Should I keep my responses shorter?"
/// - "How much memory is available for my context window?"
/// - "Is the device plugged in or running on battery?"
///
/// Uses `DeviceMetrics` for thermal and memory data, `UIDevice` for battery info
/// on iOS, and `FileManager` for disk space.
struct SystemHealthTool: Tool {
    static let name = "get_system_health"
    static let description = "Get the system health status including thermal state, memory, battery, and disk space. Useful for understanding the device's current operational constraints."

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = [:]
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
        let thermalLevel = DeviceMetrics.currentThermalLevel
        let availableMemoryMB = DeviceMetrics.availableMemoryMB
        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        // Thermal state with emoji indicator
        let thermalEmoji: String
        switch thermalLevel {
        case .nominal:  thermalEmoji = "🟢"
        case .fair:     thermalEmoji = "🟡"
        case .serious:  thermalEmoji = "🟠"
        case .critical: thermalEmoji = "🔴"
        }

        var result: [String: Any] = [
            "thermal_state": thermalLevel.label,
            "thermal_indicator": thermalEmoji,
            "thermal_symbol": thermalLevel.symbolName,
            "available_memory_mb": String(format: "%.0f", availableMemoryMB),
            "total_memory_gb": String(format: "%.1f", totalMemoryGB),
            "memory_pressure": availableMemoryMB < 500 ? "high" :
                               availableMemoryMB < 1500 ? "moderate" : "low",
            "processor_count": ProcessInfo.processInfo.processorCount,
            "active_processor_count": ProcessInfo.processInfo.activeProcessorCount
        ]

        // Battery info — iOS only via UIDevice
        #if os(iOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let batteryLevel = await MainActor.run { UIDevice.current.batteryLevel }
        let batteryState = await MainActor.run { UIDevice.current.batteryState }

        if batteryLevel >= 0 {
            result["battery_level_percent"] = Int(batteryLevel * 100)
        } else {
            result["battery_level_percent"] = "unavailable"
        }

        let batteryStateString: String
        switch batteryState {
        case .unknown:    batteryStateString = "unknown"
        case .unplugged:  batteryStateString = "unplugged"
        case .charging:   batteryStateString = "charging"
        case .full:       batteryStateString = "full"
        @unknown default: batteryStateString = "unknown"
        }
        result["battery_state"] = batteryStateString
        #else
        result["battery_level_percent"] = "not_available_on_macos"
        result["battery_state"] = "not_available_on_macos"
        #endif

        // Disk space available
        if let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            let freeSpaceGB = Double(freeSpace) / 1_073_741_824.0
            result["disk_space_available_gb"] = String(format: "%.1f", freeSpaceGB)
        } else {
            result["disk_space_available_gb"] = "unavailable"
        }

        // System uptime
        let uptime = ProcessInfo.processInfo.systemUptime
        let uptimeHours = Int(uptime / 3600)
        let uptimeMinutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
        result["system_uptime"] = "\(uptimeHours)h \(uptimeMinutes)m"

        resultString = jsonString(from: result)
        return resultString
    }
}

// MARK: - Tool Registry

/// Central registry for all built-in tools available for on-device function calling.
///
/// Usage:
/// ```swift
/// // Get all tools for ConversationConfig
/// let config = ConversationConfig(tools: ToolRegistry.defaultTools)
///
/// // Or use the convenience ToolManager
/// let manager = ToolRegistry.createToolManager()
/// ```
enum ToolRegistry {

    /// All built-in tools for on-device function calling.
    ///
    /// Every tool in this list is:
    /// - **Side-effect-free**: No network calls, no file writes, no state mutations
    /// - **Offline-capable**: Works without any internet connection
    /// - **Safe**: No arbitrary code execution, sandboxed to read-only operations
    static let defaultTools: [Tool] = [
        CalculatorTool(),
        DateTimeTool(),
        DeviceInfoTool(),
        UnitConverterTool(),
        TextAnalyzerTool(),
        SystemHealthTool()
    ]

    /// Creates a `ToolManager` pre-configured with all built-in tools.
    ///
    /// The `ToolManager` handles the tool call loop automatically (up to 25 iterations)
    /// and generates OpenAPI-compliant JSON schemas from the `@ToolParam` declarations.
    ///
    /// - Returns: A configured `ToolManager` ready for use with a conversation.
    static func createToolManager() -> ToolManager {
        ToolManager(tools: defaultTools)
    }
}
