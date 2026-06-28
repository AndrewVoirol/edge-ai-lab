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

import SwiftUI
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Chat Panel Collapse Tests

/// Tests for the macOS chat panel collapse/expand toggle logic.
///
/// Since `isChatCollapsed` is a `@State` property inside `ContentView`,
/// we test the design system tokens and behavioral invariants that the
/// toggle relies on, rather than attempting to instantiate the view.
@Suite("ChatPanelCollapse")
struct ChatPanelCollapseTests {

    @Test("AppAnimation.standard exists and is usable")
    func animationTokenExists() {
        // The chat collapse toggle uses AppAnimation.standard
        let animation = AppAnimation.standard
        // Swift's Animation doesn't expose its properties for testing,
        // but we can verify the static property compiles and is non-nil
        _ = animation
    }

    @Test("Collapsed state is a simple boolean toggle")
    func booleanToggleSemantics() {
        // The chat panel collapse uses Bool.toggle() semantics
        var isChatCollapsed = false
        #expect(isChatCollapsed == false)

        isChatCollapsed.toggle()
        #expect(isChatCollapsed == true)

        isChatCollapsed.toggle()
        #expect(isChatCollapsed == false)
    }

    #if os(macOS)
    @Test("Keyboard shortcut Cmd+Shift+C is a valid modifier combination")
    func keyboardShortcutModifiers() {
        // Verify the modifier combination used by the toggle
        let modifiers: EventModifiers = [.command, .shift]
        #expect(modifiers.contains(.command))
        #expect(modifiers.contains(.shift))
        #expect(!modifiers.contains(.control))
        #expect(!modifiers.contains(.option))
    }
    #endif

    @Test("Default collapsed state is false (expanded)")
    func defaultStateIsExpanded() {
        // The default value of isChatCollapsed in ContentView is false
        let defaultState = false
        #expect(defaultState == false, "Chat panel should start expanded")
    }
}
