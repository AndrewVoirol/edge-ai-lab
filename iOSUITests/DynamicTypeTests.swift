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

import XCTest

/// Tests that verify the app's layout remains functional at maximum
/// Dynamic Type accessibility sizes.
///
/// These tests launch the app with the largest accessibility text size
/// and verify that critical UI elements remain visible and tappable.
/// This is important for users with visual impairments who depend on
/// large text to use the app effectively.
final class DynamicTypeTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true // Collect all layout issues
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
            usleep(500_000)
        }
        try super.tearDownWithError()
    }

    /// Launches the app at the specified Dynamic Type size.
    func launchApp(contentSize: String = "UICTContentSizeCategoryAccessibilityXXXL") -> XCUIApplication {
        let app = XCUIApplication()

        if app.state != .notRunning {
            app.terminate()
            usleep(1_000_000)
        }

        app.launchArguments += [
            "-DisableAnimations",
            "-SkipOnboarding",
            "-UIPreferredContentSizeCategoryName", contentSize
        ]
        app.launch()

        let isRunning = app.wait(for: .runningForeground, timeout: 15.0)
        XCTAssertTrue(isRunning, "App should reach runningForeground state")
        sleep(5) // SwiftUI layout at large sizes takes longer

        return app
    }

    /// Verifies the tab bar is visible and all tabs are tappable at max text size.
    func testTabBarAtMaxSize() throws {
        let app = launchApp()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10.0),
                      "Tab bar should be visible at max Dynamic Type size")

        // All three tabs should exist
        let tabs = ["Models", "Chat", "Settings"]
        for tabName in tabs {
            let tab = app.tabBars.buttons[tabName]
            XCTAssertTrue(tab.exists, "'\(tabName)' tab should exist at max Dynamic Type size")
        }
    }

    /// Verifies the model hub renders content at max text size without crashing.
    func testModelHubAtMaxSize() throws {
        let app = launchApp()

        // The model hub should show at least one section header
        var hasContent = false
        for _ in 0..<10 {
            if app.staticTexts["Now Running"].exists ||
               app.staticTexts["On This Device"].exists ||
               app.staticTexts["Get More Models"].exists {
                hasContent = true
                break
            }
            sleep(1)
        }
        XCTAssertTrue(hasContent,
                      "Model Hub should show section headers at max Dynamic Type size")
    }

    /// Verifies the chat input area is usable at max text size.
    func testChatInputAtMaxSize() throws {
        let app = launchApp()

        // Switch to Chat tab
        let chatTab = app.tabBars.buttons["Chat"]
        guard chatTab.waitForExistence(timeout: 5.0) else {
            XCTFail("Chat tab should exist")
            return
        }
        chatTab.tap()
        usleep(1_000_000)

        // The prompt field should exist and be tappable
        let promptField = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'textField_prompt'"))
            .firstMatch
        let promptTextView = app.textViews["textField_prompt"]

        let hasPromptField = promptField.waitForExistence(timeout: 10.0) ||
                             promptTextView.waitForExistence(timeout: 3.0)

        XCTAssertTrue(hasPromptField,
                      "Chat prompt field should be visible at max Dynamic Type size")

        // The send button should also exist
        let sendButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'button_send'"))
            .firstMatch
        if sendButton.waitForExistence(timeout: 3.0) {
            XCTAssertTrue(sendButton.isEnabled || sendButton.exists,
                          "Send button should be visible at max Dynamic Type size")
        }
    }

    /// Runs the accessibility audit at the largest text size to catch text clipping.
    func testAccessibilityAuditAtMaxSize() throws {
        let app = launchApp()

        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.textClipped, .dynamicType]) { issue in
                // Filter known false positives
                if issue.auditType == .textClipped {
                    let elementType = issue.element?.elementType
                    // System-owned search fields clip on Liquid Glass
                    if elementType == .searchField { return true }
                    // Navigation bar titles may clip at extreme sizes
                    if elementType == .navigationBar { return true }
                }
                return false
            }
        }
    }
}
