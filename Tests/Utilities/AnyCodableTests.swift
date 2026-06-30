// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite("AnyCodable")
struct AnyCodableTests {

    // MARK: - Typed Accessors

    @Test("stringValue returns String or nil")
    func stringValue() {
        #expect(AnyCodable("hello").stringValue == "hello")
        #expect(AnyCodable(42).stringValue == nil)
        #expect(AnyCodable(true).stringValue == nil)
    }

    @Test("intValue returns Int or nil")
    func intValue() {
        #expect(AnyCodable(42).intValue == 42)
        #expect(AnyCodable("hello").intValue == nil)
        #expect(AnyCodable(3.14).intValue == nil)
    }

    @Test("doubleValue returns Double or nil")
    func doubleValue() {
        #expect(AnyCodable(3.14).doubleValue == 3.14)
        #expect(AnyCodable(42).doubleValue == nil)  // Int != Double
        #expect(AnyCodable("hello").doubleValue == nil)
    }

    @Test("boolValue returns Bool or nil")
    func boolValue() {
        #expect(AnyCodable(true).boolValue == true)
        #expect(AnyCodable(false).boolValue == false)
        #expect(AnyCodable(1).boolValue == nil)  // Int is not Bool
        #expect(AnyCodable("true").boolValue == nil)
    }

    @Test("displayString always returns a string")
    func displayString() {
        #expect(AnyCodable("hello").displayString == "hello")
        #expect(AnyCodable(42).displayString == "42")
        #expect(AnyCodable(3.14).displayString == "3.14")
        #expect(AnyCodable(true).displayString == "true")
        #expect(AnyCodable(false).displayString == "false")
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves String")
    func codableString() throws {
        let original = AnyCodable("hello world")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.stringValue == "hello world")
    }

    @Test("Codable round-trip preserves Int")
    func codableInt() throws {
        let original = AnyCodable(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.intValue == 42)
    }

    @Test("Codable round-trip preserves Bool")
    func codableBool() throws {
        let original = AnyCodable(true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.boolValue == true)
    }

    @Test("Codable round-trip preserves Double")
    func codableDouble() throws {
        let original = AnyCodable(3.14)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        #expect(decoded.doubleValue == 3.14)
    }

    @Test("Codable round-trip preserves dictionary")
    func codableDictionary() throws {
        let dict: [String: Any] = ["key": "value", "count": 5]
        let original = AnyCodable(dict)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let resultDict = decoded.dictionaryValue
        #expect(resultDict != nil)
    }

    @Test("Codable round-trip preserves array")
    func codableArray() throws {
        let arr: [Any] = [1, "two", 3.0]
        let original = AnyCodable(arr)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let resultArr = decoded.arrayValue
        #expect(resultArr != nil)
        #expect(resultArr?.count == 3)
    }

    // MARK: - Hashable

    @Test("Hashable: equal values have same hash")
    func hashable() {
        let a = AnyCodable("hello")
        let b = AnyCodable("hello")
        #expect(a.hashValue == b.hashValue)
    }

    // MARK: - Equatable

    @Test("Equatable works for same type values")
    func equatable() {
        let a = AnyCodable("hello")
        let b = AnyCodable("hello")
        let c = AnyCodable("world")
        #expect(a == b)
        #expect(a != c)
    }
}
