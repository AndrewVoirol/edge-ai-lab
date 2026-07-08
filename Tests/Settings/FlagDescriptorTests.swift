// Copyright 2026 Andrew Voirol. Apache-2.0
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for FlagDescriptor and FlagRegistry.
///
/// Verifies that the flag registry accurately reflects empirically tested engine support
/// from Phase 1/1.5. Any change to these tests should be accompanied by
/// re-running the corresponding integration test.
final class FlagDescriptorTests: XCTestCase {

    // MARK: - Engine Support (sourced from MLXFeatureVerificationTests)

    func testThinking_SupportedOnBothEngines() {
        let desc = FlagRegistry.thinking
        XCTAssertTrue(desc.isSupported(on: .litertlm), "Thinking works on LiteRT")
        XCTAssertTrue(desc.isSupported(on: .mlx), "Thinking works on MLX — verified by testMLX_Thinking_Works")
    }

    func testMTP_LiteRTOnly() {
        let desc = FlagRegistry.speculative
        XCTAssertTrue(desc.isSupported(on: .litertlm), "MTP works on LiteRT")
        XCTAssertFalse(desc.isSupported(on: .mlx), "MTP NOT supported on MLX — SDK has speculative but adapter doesn't wire it")
    }

    func testCD_LiteRTOnly() {
        let desc = FlagRegistry.constrainedDecoding
        XCTAssertTrue(desc.isSupported(on: .litertlm), "CD works on LiteRT")
        XCTAssertFalse(desc.isSupported(on: .mlx), "CD NOT in MLX — zero SDK hits per testMLX_ConstrainedDecoding_SDKSupport")
    }

    func testToolCalling_SupportedOnBothEngines() {
        let desc = FlagRegistry.toolCalling
        XCTAssertTrue(desc.isSupported(on: .litertlm))
        XCTAssertTrue(desc.isSupported(on: .mlx), "Tools on MLX — verified by testMLX_ToolCalling_EndToEnd")
    }

    func testSamplerFlags_SupportedOnAllEngines() {
        for flag in FlagRegistry.samplerFlags {
            XCTAssertTrue(flag.isSupported(on: .litertlm), "\(flag.displayName) should work on LiteRT")
            XCTAssertTrue(flag.isSupported(on: .mlx), "\(flag.displayName) should work on MLX")
            XCTAssertTrue(flag.isSupported(on: .gguf), "\(flag.displayName) should work on GGUF (empty set = all)")
        }
    }

    // MARK: - Reload Requirements

    func testThinking_AlwaysRequiresReload() {
        let desc = FlagRegistry.thinking
        XCTAssertTrue(desc.reloadRequirement.requiresReload(for: .litertlm))
        XCTAssertTrue(desc.reloadRequirement.requiresReload(for: .mlx))
    }

    func testTemperature_NeverRequiresReload() {
        let desc = FlagRegistry.temperature
        // LiteRT: hot-patches via applySamplerSettingsInPlace()
        // MLX: rebuilds GenerateParameters per-generation
        XCTAssertFalse(desc.reloadRequirement.requiresReload(for: .litertlm))
        XCTAssertFalse(desc.reloadRequirement.requiresReload(for: .mlx))
    }

    // MARK: - Registry Completeness

    func testRegistryContainsAllFeatureFlags() {
        let ids = Set(FlagRegistry.featureFlags.map(\.id))
        XCTAssertTrue(ids.contains("thinking"))
        XCTAssertTrue(ids.contains("mtp"))
        XCTAssertTrue(ids.contains("cd"))
        XCTAssertTrue(ids.contains("tools"))
    }

    func testRegistryLookupById() {
        XCTAssertNotNil(FlagRegistry.descriptor(for: "thinking"))
        XCTAssertNotNil(FlagRegistry.descriptor(for: "temperature"))
        XCTAssertNil(FlagRegistry.descriptor(for: "nonexistent"))
    }

    func testAllFlagsHaveUniqueIds() {
        let ids = FlagRegistry.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All flag IDs must be unique")
    }

    func testAllFlagsHaveDescriptions() {
        for flag in FlagRegistry.all {
            XCTAssertFalse(flag.description.isEmpty, "\(flag.displayName) must have a description")
        }
    }
}
