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

// MARK: - AnySendable

/// Sendable wrapper for `Any`, enabling use in concurrent Swift code.
///
/// Uses `@unchecked Sendable` because the underlying value's Sendability
/// cannot be verified at compile time.
public struct AnySendable: @unchecked Sendable, Hashable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public static func == (lhs: AnySendable, rhs: AnySendable) -> Bool {
        // Use string representation for equality — intentionally coarse.
        String(describing: lhs.value) == String(describing: rhs.value)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(String(describing: value))
    }
}

// MARK: - AnyCodable

/// Type-erased Codable wrapper for arbitrary JSON values.
///
/// Supports: `null`, `Bool`, `Int`, `Double`, `String`, `[Any]`, `[String: Any]`.
///
/// Originally defined in `MCPClient.swift` for MCP schema persistence.
/// Extracted here so `AppToolCall` and other cross-module types can use it
/// without depending on the MCP subsystem.
///
/// ## Usage in Tool Call Arguments
///
/// ```swift
/// let call = AppToolCall(
///     id: "1",
///     toolName: "search",
///     arguments: [
///         "query": AnyCodable("weather"),
///         "limit": AnyCodable(5),
///         "filters": AnyCodable(["city": "SF", "country": "US"])
///     ]
/// )
/// // Extract typed values:
/// let query = call.arguments["query"]?.stringValue   // "weather"
/// let limit = call.arguments["limit"]?.intValue       // 5
/// ```
public struct AnyCodable: Codable, Hashable, Sendable {
    public let value: AnySendable

    public init(_ value: Any) {
        self.value = AnySendable(value)
    }

    // MARK: - Typed Accessors

    /// Extract the underlying value as a `String`, or nil if it's not a string.
    public var stringValue: String? {
        value.value as? String
    }

    /// Extract the underlying value as an `Int`, or nil if it's not an integer.
    public var intValue: Int? {
        value.value as? Int
    }

    /// Extract the underlying value as a `Double`, or nil if it's not numeric.
    public var doubleValue: Double? {
        value.value as? Double
    }

    /// Extract the underlying value as a `Bool`, or nil if it's not boolean.
    public var boolValue: Bool? {
        value.value as? Bool
    }

    /// Extract the underlying value as a `[String: Any]` dictionary, or nil.
    public var dictionaryValue: [String: Any]? {
        value.value as? [String: Any]
    }

    /// Extract the underlying value as a `[Any]` array, or nil.
    public var arrayValue: [Any]? {
        value.value as? [Any]
    }

    /// String description of the value, suitable for display or logging.
    /// Always returns a non-nil string. For structured values, returns their
    /// `String(describing:)` representation.
    public var displayString: String {
        if let s = stringValue { return s }
        if let i = intValue { return String(i) }
        if let d = doubleValue { return String(d) }
        if let b = boolValue { return b ? "true" : "false" }
        return String(describing: value.value)
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = AnySendable(NSNull())
        } else if let bool = try? container.decode(Bool.self) {
            self.value = AnySendable(bool)
        } else if let int = try? container.decode(Int.self) {
            self.value = AnySendable(int)
        } else if let double = try? container.decode(Double.self) {
            self.value = AnySendable(double)
        } else if let string = try? container.decode(String.self) {
            self.value = AnySendable(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = AnySendable(array.map { $0.value.value })
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            var rawDict: [String: Any] = [:]
            for (k, v) in dict {
                rawDict[k] = v.value.value
            }
            self.value = AnySendable(rawDict)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode AnyCodable"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try encodeValue(value.value, to: &container)
    }

    private func encodeValue(_ val: Any, to container: inout SingleValueEncodingContainer) throws {
        if val is NSNull {
            try container.encodeNil()
        } else if let bool = val as? Bool {
            try container.encode(bool)
        } else if let int = val as? Int {
            try container.encode(int)
        } else if let double = val as? Double {
            try container.encode(double)
        } else if let string = val as? String {
            try container.encode(string)
        } else if let array = val as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        } else if let dict = val as? [String: Any] {
            var codableDict: [String: AnyCodable] = [:]
            for (k, v) in dict {
                codableDict[k] = AnyCodable(v)
            }
            try container.encode(codableDict)
        } else {
            try container.encode(String(describing: val))
        }
    }
}
