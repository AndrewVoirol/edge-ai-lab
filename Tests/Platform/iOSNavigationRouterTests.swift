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

// MARK: - AppTab Tests

/// Tests for the `AppTab` enum — type-safe tab identifiers for the iOS TabView.
///
/// These tests verify:
/// - Correct number of cases (guard against silent additions)
/// - Hashable conformance for TabView selection binding
/// - CaseIterable for reachability testing
/// - Expected raw values for debugging/logging
@Suite("AppTab")
struct AppTabTests {

    @Test("has exactly 4 cases — models, chat, evaluations, settings")
    func caseCount() {
        #if os(iOS)
        #expect(AppTab.allCases.count == 4, "AppTab should have exactly 4 cases")
        #else
        // AppTab is iOS-only — skip on macOS
        withKnownIssue("AppTab is only available on iOS") {
            Issue.record("AppTab is iOS-only — this test should only run on iOS")
        }
        #endif
    }

    @Test("all cases are distinct via Hashable conformance")
    func hashableDistinctness() {
        #if os(iOS)
        let allCases = AppTab.allCases
        _ = Set(allCases.map { $0.hashValue })
        // In practice hash collisions are possible, but for 4 trivial enum cases they shouldn't collide
        #expect(allCases.count == Set(allCases).count, "All AppTab cases should be unique in a Set")
        #else
        // AppTab is iOS-only
        #endif
    }

    @Test("raw values match expected strings")
    func rawValues() {
        #if os(iOS)
        #expect(AppTab.models.rawValue == "models")
        #expect(AppTab.chat.rawValue == "chat")
        #expect(AppTab.evaluations.rawValue == "evaluations")
        #expect(AppTab.settings.rawValue == "settings")
        #else
        // AppTab is iOS-only
        #endif
    }
}

// MARK: - iOSNavigationRouter Tests

/// TDD tests for `iOSNavigationRouter` — centralized navigation state for iOS.
///
/// These tests were written BEFORE the implementation (Red phase of TDD).
/// They verify:
/// - Default state (starts on Models tab)
/// - Programmatic navigation to every tab
/// - Models path management (push/pop/reset)
/// - Reachability (every tab is always reachable)
/// - Round-trip navigation preserves state
@Suite("iOSNavigationRouter")
struct iOSNavigationRouterTests {

    // MARK: - Default State

    @Test("default tab is .models")
    func defaultTab() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        #expect(router.selectedTab == .models, "Router should default to the Models tab")
        #else
        // iOS-only
        #endif
    }

    @Test("default models path is empty")
    func defaultModelsPath() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        #expect(router.modelsPath.isEmpty, "Models navigation path should start empty")
        #else
        // iOS-only
        #endif
    }

    // MARK: - Navigation Actions

    @Test("navigateToChat switches to .chat")
    func navigateToChat() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        router.navigateToChat()
        #expect(router.selectedTab == .chat)
        #endif
    }

    @Test("navigateToModels switches to .models")
    func navigateToModels() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        // Start on a different tab
        router.selectedTab = .chat
        router.navigateToModels()
        #expect(router.selectedTab == .models)
        #endif
    }

    @Test("navigateToModels with resetStack clears modelsPath")
    func navigateToModelsResetsStack() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        // Simulate a pushed detail view
        router.modelsPath.append("some-model-id")
        #expect(!router.modelsPath.isEmpty, "Precondition: path should have an item")

        router.navigateToModels(resetStack: true)
        #expect(router.selectedTab == .models)
        #expect(router.modelsPath.isEmpty, "resetStack should clear the models path")
        #endif
    }

    @Test("navigateToModels without resetStack preserves modelsPath")
    func navigateToModelsPreservesStack() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        router.modelsPath.append("some-model-id")
        router.selectedTab = .chat

        router.navigateToModels(resetStack: false)
        #expect(router.selectedTab == .models)
        #expect(!router.modelsPath.isEmpty, "Path should be preserved when resetStack is false")
        #endif
    }

    @Test("navigateToEvaluations switches to .evaluations")
    func navigateToEvaluations() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        router.navigateToEvaluations()
        #expect(router.selectedTab == .evaluations)
        #endif
    }

    @Test("navigateToSettings switches to .settings")
    func navigateToSettings() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        router.navigateToSettings()
        #expect(router.selectedTab == .settings)
        #endif
    }

    // MARK: - Reachability

    @Test("every tab is reachable from the router",
          arguments: [
            "models", "chat", "evaluations", "settings"
          ])
    func allTabsReachable(tabRawValue: String) {
        #if os(iOS)
        let router = iOSNavigationRouter()
        guard let tab = AppTab(rawValue: tabRawValue) else {
            Issue.record("Unknown tab raw value: \(tabRawValue)")
            return
        }
        #expect(router.canNavigate(to: tab), "\(tab) should be reachable")
        #endif
    }

    @Test("can navigate to every tab by setting selectedTab directly")
    func directTabSelection() {
        #if os(iOS)
        let router = iOSNavigationRouter()
        for tab in AppTab.allCases {
            router.selectedTab = tab
            #expect(router.selectedTab == tab, "Should be able to select \(tab)")
        }
        #endif
    }

    // MARK: - Round-Trip Navigation

    @Test("round-trip models → chat → models preserves modelsPath state")
    func roundTripPreservesState() {
        #if os(iOS)
        let router = iOSNavigationRouter()

        // Push a detail view
        router.modelsPath.append("gemma-4-e2b")
        let pathCountBefore = router.modelsPath.count

        // Navigate away to Chat
        router.navigateToChat()
        #expect(router.selectedTab == .chat)

        // Navigate back to Models (without reset)
        router.navigateToModels()
        #expect(router.selectedTab == .models)
        #expect(router.modelsPath.count == pathCountBefore,
                "Round-trip should preserve the models path state")
        #endif
    }

    @Test("rapid tab switching settles on the last selection")
    func rapidTabSwitching() {
        #if os(iOS)
        let router = iOSNavigationRouter()

        // Simulate rapid tab switching
        router.navigateToChat()
        router.navigateToEvaluations()
        router.navigateToSettings()
        router.navigateToModels()
        router.navigateToChat()

        #expect(router.selectedTab == .chat,
                "After rapid switching, the last call should win")
        #endif
    }
}
