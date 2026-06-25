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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Test Helpers

/// Thin wrapper so we can decode `{"value": <anything>}` via JSONDecoder.
private struct AnyDecodableWrapper: Decodable {
    let value: AnyDecodable
}

/// Convenience: decode a JSON string through the wrapper and return the unwrapped `Any`.
private func decodeValue(_ json: String) throws -> Any {
    let data = try #require(json.data(using: .utf8))
    let wrapper = try JSONDecoder().decode(AnyDecodableWrapper.self, from: data)
    return wrapper.value.value
}

// MARK: - AnyDecodable Tests

@Suite("AnyDecodable")
struct AnyDecodableTests {

    // MARK: Null

    @Test("Decodes JSON null as NSNull")
    func decodesNull() throws {
        let result = try decodeValue(#"{"value": null}"#)
        #expect(result is NSNull)
    }

    // MARK: Booleans

    @Test("Decodes true")
    func decodesTrue() throws {
        let result = try decodeValue(#"{"value": true}"#)
        let bool = try #require(result as? Bool)
        #expect(bool == true)
    }

    @Test("Decodes false")
    func decodesFalse() throws {
        let result = try decodeValue(#"{"value": false}"#)
        let bool = try #require(result as? Bool)
        #expect(bool == false)
    }

    // MARK: Integers

    @Test("Decodes integer")
    func decodesInt() throws {
        let result = try decodeValue(#"{"value": 42}"#)
        let int = try #require(result as? Int)
        #expect(int == 42)
    }

    @Test("Decodes zero integer")
    func decodesZero() throws {
        let result = try decodeValue(#"{"value": 0}"#)
        // 0 should decode as Int (Bool decoding is tried first but JSON 0 != false for JSONDecoder)
        let int = try #require(result as? Int)
        #expect(int == 0)
    }

    @Test("Decodes negative integer")
    func decodesNegativeInt() throws {
        let result = try decodeValue(#"{"value": -7}"#)
        let int = try #require(result as? Int)
        #expect(int == -7)
    }

    // MARK: Doubles

    @Test("Decodes floating-point number as Double")
    func decodesDouble() throws {
        let result = try decodeValue(#"{"value": 3.14}"#)
        let double = try #require(result as? Double)
        #expect(abs(double - 3.14) < 0.001)
    }

    @Test("Decodes negative floating-point number")
    func decodesNegativeDouble() throws {
        let result = try decodeValue(#"{"value": -0.5}"#)
        let double = try #require(result as? Double)
        #expect(abs(double - (-0.5)) < 0.001)
    }

    // MARK: Strings

    @Test("Decodes string")
    func decodesString() throws {
        let result = try decodeValue(#"{"value": "hello"}"#)
        let str = try #require(result as? String)
        #expect(str == "hello")
    }

    @Test("Decodes empty string")
    func decodesEmptyString() throws {
        let result = try decodeValue(#"{"value": ""}"#)
        let str = try #require(result as? String)
        #expect(str == "")
    }

    @Test("Decodes string with special characters")
    func decodesSpecialCharString() throws {
        let result = try decodeValue(#"{"value": "line1\nline2"}"#)
        let str = try #require(result as? String)
        #expect(str.contains("\n"))
    }

    // MARK: Arrays

    @Test("Decodes mixed-type array")
    func decodesMixedArray() throws {
        let result = try decodeValue(#"{"value": [1, "two", true]}"#)
        let array = try #require(result as? [Any])
        #expect(array.count == 3)
        #expect(array[0] as? Int == 1)
        #expect(array[1] as? String == "two")
        #expect(array[2] as? Bool == true)
    }

    @Test("Decodes empty array")
    func decodesEmptyArray() throws {
        let result = try decodeValue(#"{"value": []}"#)
        let array = try #require(result as? [Any])
        #expect(array.isEmpty)
    }

    @Test("Decodes array of integers")
    func decodesIntArray() throws {
        let result = try decodeValue(#"{"value": [10, 20, 30]}"#)
        let array = try #require(result as? [Any])
        #expect(array.count == 3)
        #expect(array[0] as? Int == 10)
        #expect(array[1] as? Int == 20)
        #expect(array[2] as? Int == 30)
    }

    // MARK: Dictionaries

    @Test("Decodes nested dictionary")
    func decodesNestedDict() throws {
        let result = try decodeValue(#"{"value": {"key": "val"}}"#)
        let dict = try #require(result as? [String: Any])
        #expect(dict["key"] as? String == "val")
    }

    @Test("Decodes empty dictionary")
    func decodesEmptyDict() throws {
        let result = try decodeValue(#"{"value": {}}"#)
        let dict = try #require(result as? [String: Any])
        #expect(dict.isEmpty)
    }

    @Test("Decodes dictionary with mixed value types")
    func decodesMixedDict() throws {
        let json = #"{"value": {"name": "test", "count": 5, "active": true}}"#
        let result = try decodeValue(json)
        let dict = try #require(result as? [String: Any])
        #expect(dict["name"] as? String == "test")
        #expect(dict["count"] as? Int == 5)
        #expect(dict["active"] as? Bool == true)
    }

    // MARK: Deeply Nested

    @Test("Decodes deeply nested structure")
    func decodesDeepNesting() throws {
        let json = """
        {"value": {"level1": {"level2": {"level3": "deep"}}}}
        """
        let result = try decodeValue(json)
        let l1 = try #require(result as? [String: Any])
        let l2 = try #require(l1["level1"] as? [String: Any])
        let l3 = try #require(l2["level2"] as? [String: Any])
        #expect(l3["level3"] as? String == "deep")
    }

    @Test("Decodes array containing dictionaries")
    func decodesArrayOfDicts() throws {
        let json = #"{"value": [{"a": 1}, {"b": 2}]}"#
        let result = try decodeValue(json)
        let array = try #require(result as? [Any])
        #expect(array.count == 2)
        let first = try #require(array[0] as? [String: Any])
        #expect(first["a"] as? Int == 1)
        let second = try #require(array[1] as? [String: Any])
        #expect(second["b"] as? Int == 2)
    }

    @Test("Decodes dictionary containing arrays")
    func decodesDictWithArrays() throws {
        let json = #"{"value": {"nums": [1, 2, 3], "strs": ["a", "b"]}}"#
        let result = try decodeValue(json)
        let dict = try #require(result as? [String: Any])
        let nums = try #require(dict["nums"] as? [Any])
        #expect(nums.count == 3)
        let strs = try #require(dict["strs"] as? [Any])
        #expect(strs.count == 2)
        #expect(strs[0] as? String == "a")
    }

    @Test("Decodes array with null element")
    func decodesArrayWithNull() throws {
        let json = #"{"value": [null, 1, "two"]}"#
        let result = try decodeValue(json)
        let array = try #require(result as? [Any])
        #expect(array.count == 3)
        #expect(array[0] is NSNull)
        #expect(array[1] as? Int == 1)
        #expect(array[2] as? String == "two")
    }
}

// MARK: - DynamicKey Tests

@Suite("DynamicKey")
struct DynamicKeyTests {

    @Test("init with stringValue succeeds")
    func initWithStringValue() throws {
        let key = try #require(DynamicKey(stringValue: "myKey"))
        #expect(key.stringValue == "myKey")
    }

    @Test("stringValue preserves input including special characters")
    func stringValuePreservesInput() throws {
        let key = try #require(DynamicKey(stringValue: "some.dotted.key"))
        #expect(key.stringValue == "some.dotted.key")
    }

    @Test("stringValue preserves empty string")
    func stringValueEmpty() throws {
        let key = try #require(DynamicKey(stringValue: ""))
        #expect(key.stringValue == "")
    }

    @Test("init with intValue returns nil")
    func initWithIntValueReturnsNil() {
        let key = DynamicKey(intValue: 42)
        #expect(key == nil)
    }

    @Test("init with intValue zero returns nil")
    func initWithIntValueZeroReturnsNil() {
        let key = DynamicKey(intValue: 0)
        #expect(key == nil)
    }

    @Test("intValue is always nil")
    func intValueAlwaysNil() throws {
        let key = try #require(DynamicKey(stringValue: "test"))
        #expect(key.intValue == nil)
    }
}

// MARK: - MCPBridgeManager Tests (minimal)

@Suite("MCPBridgeManager")
struct MCPBridgeManagerTests {

    @Test("shared returns the same instance")
    func sharedIsSameInstance() {
        let a = MCPBridgeManager.shared
        let b = MCPBridgeManager.shared
        #expect(a === b)
    }

    @Test("clear does not crash when called on empty manager")
    func clearDoesNotCrash() {
        // Calling clear on a freshly-accessed manager must not trap.
        MCPBridgeManager.shared.clear()
    }

    @Test("clear can be called multiple times safely")
    func clearMultipleTimes() {
        MCPBridgeManager.shared.clear()
        MCPBridgeManager.shared.clear()
        MCPBridgeManager.shared.clear()
        // Reaching here without crashing is the assertion.
    }
}
