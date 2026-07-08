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

/// Tests for ActiveConfigBadges badge computation logic.
///
/// Tests the static `visibleBadges` method — pure function, no SwiftUI rendering needed.
final class ActiveConfigBadgesTests: XCTestCase {

    // MARK: - Visibility Rules

    func testAllFeaturesDisabled_NoBadges() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: nil,
            enableConversationConstrainedDecoding: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        XCTAssertTrue(badges.isEmpty, "No badges when all features are off")
    }

    func testThinkingEnabled_ShowsBadge() {
        let flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: false,
            enableAgentSkills: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.flagId, "thinking")
        XCTAssertTrue(badges.first?.isSupported ?? false, "Thinking is supported on LiteRT")
    }

    func testAllFeaturesEnabled_ShowsAllBadges() {
        var flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: true,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        XCTAssertEqual(badges.count, 4, "Should show Think, MTP, CD, Tools")
        let ids = Set(badges.map(\.flagId))
        XCTAssertTrue(ids.contains("thinking"))
        XCTAssertTrue(ids.contains("mtp"))
        XCTAssertTrue(ids.contains("cd"))
        XCTAssertTrue(ids.contains("tools"))
    }

    // MARK: - Engine Support

    func testMLX_MTPEnabled_ShowsUnsupported() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .mlx)
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.flagId, "mtp")
        XCTAssertFalse(badges.first?.isSupported ?? true,
                       "MTP is NOT supported on MLX — should show unsupported state")
    }

    func testMLX_CDEnabled_ShowsUnsupported() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableConversationConstrainedDecoding: true
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .mlx)
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.flagId, "cd")
        XCTAssertFalse(badges.first?.isSupported ?? true,
                       "CD is NOT supported on MLX — zero SDK hits")
    }

    func testMLX_ThinkingEnabled_ShowsSupported() {
        let flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: false,
            enableAgentSkills: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .mlx)
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.flagId, "thinking")
        XCTAssertTrue(badges.first?.isSupported ?? false,
                      "Thinking IS supported on MLX — verified by testMLX_Thinking_Works")
    }

    func testMLX_ToolsEnabled_ShowsSupported() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: true,
            enableAgentSkills: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .mlx)
        XCTAssertEqual(badges.count, 1)
        XCTAssertEqual(badges.first?.flagId, "tools")
        XCTAssertTrue(badges.first?.isSupported ?? false,
                      "Tools ARE supported on MLX — verified by testMLX_ToolCalling_EndToEnd")
    }

    // MARK: - Mixed Scenarios

    func testMLX_MixedFeatures_CorrectSupportStates() {
        let flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: true,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .mlx)
        XCTAssertEqual(badges.count, 4)

        let byId = Dictionary(uniqueKeysWithValues: badges.map { ($0.flagId, $0) })
        XCTAssertTrue(byId["thinking"]?.isSupported ?? false, "Thinking supported on MLX")
        XCTAssertFalse(byId["mtp"]?.isSupported ?? true, "MTP unsupported on MLX")
        XCTAssertFalse(byId["cd"]?.isSupported ?? true, "CD unsupported on MLX")
        XCTAssertTrue(byId["tools"]?.isSupported ?? false, "Tools supported on MLX")
    }

    // MARK: - Badge Order

    func testBadgeOrder_ThinkMTPCDTools() {
        var flags = RuntimeFlags(
            enableThinking: true,
            enableToolCalling: true,
            enableAgentSkills: false,
            enableSpeculativeDecoding: true,
            enableConversationConstrainedDecoding: true
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        let order = badges.map(\.flagId)
        XCTAssertEqual(order, ["thinking", "mtp", "cd", "tools"],
                       "Badges should appear in fixed order: Think, MTP, CD, Tools")
    }

    // MARK: - Speculative Decoding nil vs false

    func testSpeculativeDecoding_NilMeansHidden() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: nil
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        XCTAssertTrue(badges.isEmpty, "nil speculative decoding = hidden, not shown")
    }

    func testSpeculativeDecoding_FalseMeansHidden() {
        let flags = RuntimeFlags(
            enableThinking: false,
            enableToolCalling: false,
            enableAgentSkills: false,
            enableSpeculativeDecoding: false
        )
        let badges = ActiveConfigBadges.visibleBadges(flags: flags, runtime: .litertlm)
        XCTAssertTrue(badges.isEmpty, "false speculative decoding = hidden")
    }
}
