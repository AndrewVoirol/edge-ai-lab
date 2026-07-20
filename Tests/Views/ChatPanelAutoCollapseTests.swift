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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Chat Panel Auto-Collapse Tests

/// Tests for the `shouldHideChatPanel` auto-collapse decision logic in `ContentView`.
///
/// The computed property is private inside a SwiftUI view, so we replicate its
/// pure boolean logic here as a standalone function and verify every branch.
///
/// Source truth: `ContentView.shouldHideChatPanel` (macOS only):
/// ```
/// if userExplicitlyCollapsed { return true }
/// if isChatCollapsed { return true }
/// if !isEngineReady && activeCapabilityProfile == nil { return true }
/// return false
/// ```
@Suite("ChatPanelAutoCollapse")
struct ChatPanelAutoCollapseTests {

    // MARK: - Decision Function Under Test

    /// Replicates the `shouldHideChatPanel` decision logic from ContentView.
    private static func shouldHideChatPanel(
        userExplicitlyCollapsed: Bool,
        isChatCollapsed: Bool,
        isEngineReady: Bool,
        hasActiveModel: Bool
    ) -> Bool {
        if userExplicitlyCollapsed { return true }
        if isChatCollapsed { return true }
        if !isEngineReady && !hasActiveModel { return true }
        return false
    }

    // MARK: - Auto-Collapse (No Model Loaded)

    @Test("No model loaded and no user collapse hides panel (auto-collapse)")
    func noModelLoaded_autoCollapses() {
        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: false,
            isEngineReady: false,
            hasActiveModel: false
        )
        #expect(result == true, "Panel should auto-hide when no model is loaded")
    }

    // MARK: - Model Loaded (Engine Ready)

    @Test("Model loaded with engine ready and no user collapse shows panel")
    func modelLoaded_engineReady_showsPanel() {
        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: false,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(result == false, "Panel should be visible when engine is ready")
    }

    // MARK: - User Explicit Collapse

    @Test("Model loaded but user explicitly collapsed hides panel")
    func modelLoaded_userCollapsed_hidesPanel() {
        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: true,
            isChatCollapsed: false,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(result == true, "User explicit collapse overrides model-ready state")
    }

    // MARK: - isChatCollapsed Flag

    @Test("No model, user un-collapsed, but isChatCollapsed true hides panel")
    func noModel_chatCollapsedFlag_hidesPanel() {
        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: true,
            isEngineReady: false,
            hasActiveModel: false
        )
        #expect(result == true, "isChatCollapsed flag alone should hide the panel")
    }

    // MARK: - Engine Ready Transition

    @Test("Engine ready transition from false to true shows panel")
    func engineReadyTransition_showsPanel() {
        // Before engine is ready
        let hiddenBefore = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: false,
            isEngineReady: false,
            hasActiveModel: false
        )
        #expect(hiddenBefore == true, "Panel hidden before engine ready")

        // After engine becomes ready
        let hiddenAfter = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: false,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(hiddenAfter == false, "Panel should show after engine becomes ready")
    }

    // MARK: - User Toggle Tracking

    @Test("User toggles collapse manually tracks the flag")
    func userToggle_tracksFlag() {
        var userExplicitlyCollapsed = false

        // User collapses
        userExplicitlyCollapsed.toggle()
        let hiddenAfterCollapse = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: userExplicitlyCollapsed,
            isChatCollapsed: false,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(hiddenAfterCollapse == true, "Panel should hide after user toggles collapse")

        // User expands again
        userExplicitlyCollapsed.toggle()
        let hiddenAfterExpand = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: userExplicitlyCollapsed,
            isChatCollapsed: false,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(hiddenAfterExpand == false, "Panel should show after user toggles expand")
    }

    // MARK: - Model Load Resets Flags

    @Test("After model loads both flags reset and panel shows")
    func modelLoad_resetFlags_showsPanel() {
        // Simulate state before model load: both flags could be in any state
        var userExplicitlyCollapsed = true
        var isChatCollapsed = true

        // Model finishes loading — the app resets both flags
        userExplicitlyCollapsed = false
        isChatCollapsed = false

        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: userExplicitlyCollapsed,
            isChatCollapsed: isChatCollapsed,
            isEngineReady: true,
            hasActiveModel: true
        )
        #expect(result == false, "Panel should show after model loads and flags reset")
    }

    // MARK: - Edge Case: hasActiveModel Without Engine Ready

    @Test("Active model metadata present but engine not ready shows panel")
    func activeModel_engineNotReady_showsPanel() {
        // hasActiveModel true but isEngineReady false — the third guard
        // requires BOTH to be false to hide, so having a model is enough.
        let result = Self.shouldHideChatPanel(
            userExplicitlyCollapsed: false,
            isChatCollapsed: false,
            isEngineReady: false,
            hasActiveModel: true
        )
        #expect(result == false, "Panel should show when model metadata exists even if engine isn't ready yet")
    }
}
