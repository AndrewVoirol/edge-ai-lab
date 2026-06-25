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

#if os(iOS)
import SwiftUI

// MARK: - iOS Navigation Router

/// Centralized navigation state for the iOS TabView layout.
///
/// Architecture:
/// - Owns `selectedTab` (which tab is active) and `modelsPath` (NavigationStack state
///   for the Models tab). Other tabs use implicit NavigationStack paths since they
///   don't need programmatic push/pop.
/// - Injected via `.environment(router)` at the app level.
/// - Child views read the router from the environment to perform cross-tab navigation
///   (e.g., Chat tab's "Select a Model" button switches to Models tab).
///
/// Design rationale (per Apple HIG):
/// - Each tab maintains its own NavigationStack — the router manages cross-tab state only.
/// - Tab switches are animated by SwiftUI's TabView binding; no custom transitions needed.
/// - The router does NOT auto-navigate after model load (this is a research lab, not a chat app).
///
/// Testability:
/// - All navigation logic is pure state mutation — testable without SwiftUI views.
@Observable
final class iOSNavigationRouter {

    // MARK: - Tab State

    /// The currently selected tab.
    var selectedTab: AppTab = .models

    // MARK: - Navigation Stack Paths

    /// Navigation path for the Models tab.
    /// Managed explicitly so the router can programmatically push/pop the detail view.
    var modelsPath = NavigationPath()

    // MARK: - Navigation Actions

    /// Switch to the Chat tab.
    func navigateToChat() {
        selectedTab = .chat
    }

    /// Switch to the Models tab.
    /// - Parameter resetStack: If true, pops all pushed views (e.g., model detail)
    ///   so the user lands on the Model Hub root.
    func navigateToModels(resetStack: Bool = false) {
        if resetStack {
            modelsPath = NavigationPath()
        }
        selectedTab = .models
    }

    /// Switch to the Evaluations tab.
    func navigateToEvaluations() {
        selectedTab = .evaluations
    }

    /// Switch to the Settings tab.
    func navigateToSettings() {
        selectedTab = .settings
    }

    /// Check if a given tab is reachable from the current state.
    /// Always returns true — every tab is always reachable via the tab bar.
    /// This method exists for testability: navigation reachability tests
    /// can assert that the router provides a path to every tab.
    func canNavigate(to tab: AppTab) -> Bool {
        true
    }
}
#endif
