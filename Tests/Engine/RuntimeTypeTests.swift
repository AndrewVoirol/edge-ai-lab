// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - RuntimeTypeTests

/// Tests for the `RuntimeType` enum properties and conformances.
@Suite("RuntimeType")
struct RuntimeTypeTests {

    // MARK: - Case Existence

    @Test("All expected cases exist")
    func allExpectedCasesExist() {
        // Verify each case can be constructed
        let litertlm: RuntimeType = .litertlm
        let mlx: RuntimeType = .mlx
        let gguf: RuntimeType = .gguf

        #expect(litertlm == .litertlm)
        #expect(mlx == .mlx)
        #expect(gguf == .gguf)
    }

    // MARK: - CaseIterable

    @Test("CaseIterable has exactly 3 cases")
    func caseIterableHasThreeCases() {
        // NOTE: If you add a new RuntimeType case, update this count AND the
        // matching assertion in Tests/Models/ModelMetadataTests.swift (line ~143).
        #expect(RuntimeType.allCases.count == 3)
    }

    @Test("allCases contains all expected values")
    func allCasesContainsExpectedValues() {
        let cases = RuntimeType.allCases
        #expect(cases.contains(.litertlm))
        #expect(cases.contains(.mlx))
        #expect(cases.contains(.gguf))
    }

    // MARK: - displayName

    @Test("displayName returns non-empty string for all cases")
    func displayNameNonEmptyForAllCases() {
        for runtimeType in RuntimeType.allCases {
            #expect(!runtimeType.displayName.isEmpty,
                    "\(runtimeType) should have a non-empty displayName")
        }
    }

    @Test("displayName matches raw value")
    func displayNameMatchesRawValue() {
        for runtimeType in RuntimeType.allCases {
            #expect(runtimeType.displayName == runtimeType.rawValue)
        }
    }

    @Test("displayName values are human-readable")
    func displayNameValuesAreReadable() {
        #expect(RuntimeType.litertlm.displayName == "LiteRT-LM")
        #expect(RuntimeType.mlx.displayName == "MLX")
        #expect(RuntimeType.gguf.displayName == "GGUF")
    }

    // MARK: - isSupported

    @Test("LiteRT-LM is supported")
    func litertlmIsSupported() {
        #expect(RuntimeType.litertlm.isSupported == true)
    }

    @Test("MLX is supported")
    func mlxIsSupported() {
        #expect(RuntimeType.mlx.isSupported == true)
    }

    @Test("GGUF is supported")
    func ggufIsSupported() {
        #expect(RuntimeType.gguf.isSupported == true)
    }

    // MARK: - supportedCases

    @Test("supportedCases contains LiteRT-LM and MLX")
    func supportedCasesContainsExpected() {
        let supported = RuntimeType.supportedCases
        #expect(supported.contains(.litertlm))
        #expect(supported.contains(.mlx))
    }

    @Test("supportedCases contains GGUF")
    func supportedCasesIncludesGguf() {
        let supported = RuntimeType.supportedCases
        #expect(supported.contains(.gguf))
    }

    @Test("supportedCases has exactly 3 entries")
    func supportedCasesHasThreeEntries() {
        #expect(RuntimeType.supportedCases.count == 3)
    }

    // MARK: - Identifiable

    @Test("id matches rawValue for all cases")
    func idMatchesRawValue() {
        for runtimeType in RuntimeType.allCases {
            #expect(runtimeType.id == runtimeType.rawValue,
                    "\(runtimeType).id should match rawValue")
        }
    }

    @Test("Each case has a unique id")
    func eachCaseHasUniqueId() {
        let ids = RuntimeType.allCases.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "All RuntimeType ids should be unique")
    }

    // MARK: - iconName

    @Test("iconName returns non-empty string for all cases")
    func iconNameNonEmptyForAllCases() {
        for runtimeType in RuntimeType.allCases {
            #expect(!runtimeType.iconName.isEmpty,
                    "\(runtimeType) should have a non-empty iconName")
        }
    }

    @Test("iconName returns expected SF Symbol names")
    func iconNameReturnsExpectedSymbols() {
        #expect(RuntimeType.litertlm.iconName == "cpu")
        #expect(RuntimeType.mlx.iconName == "apple.logo")
        #expect(RuntimeType.gguf.iconName == "memorychip")
    }

    // MARK: - fileExtension

    @Test("fileExtension returns expected values")
    func fileExtensionReturnsExpectedValues() {
        #expect(RuntimeType.litertlm.fileExtension == "litertlm")
        #expect(RuntimeType.mlx.fileExtension == "safetensors")
        #expect(RuntimeType.gguf.fileExtension == "gguf")
    }

    // MARK: - Codable Round-Trip

    @Test("Codable round-trip preserves all cases")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for runtimeType in RuntimeType.allCases {
            let data = try encoder.encode(runtimeType)
            let decoded = try decoder.decode(RuntimeType.self, from: data)
            #expect(decoded == runtimeType,
                    "\(runtimeType) should survive Codable round-trip")
        }
    }
}
