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

final class EdgeAILabUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Handle macOS sandboxing / permission dialogs automatically
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            let okButton = alert.buttons["OK"]
            if okButton.exists {
                okButton.click()
                return true
            }
            let allowButton = alert.buttons["Allow"]
            if allowButton.exists {
                allowButton.click()
                return true
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        // Ensure the app is fully terminated between tests to prevent
        // stale state from causing subsequent test failures on macOS.
        let app = XCUIApplication()
        if app.state != .notRunning {
            app.terminate()
            // Brief pause to allow process teardown
            usleep(500_000)
        }
        try super.tearDownWithError()
    }

    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()

        // Terminate any existing instance to ensure clean launch state.
        if app.state != .notRunning {
            app.terminate()
            usleep(1_000_000) // 1s pause for full process teardown
        }

        app.launchArguments = [
            "-DisableAnimations",
            "-SkipOnboarding",
            // Disable macOS window state restoration. After XCUITest terminate(),
            // macOS saves the state as "0 windows open." Without these flags,
            // the next launch restores that empty state = no window created.
            "-NSQuitAlwaysKeepsWindows", "0",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()

        // Step 1: Wait for the app process to reach running foreground
        let isRunning = app.wait(for: .runningForeground, timeout: 15.0)
        XCTAssertTrue(isRunning, "App should reach runningForeground state")

        // Step 2: Activate and give the menu bar time to load
        app.activate()
        sleep(2)

        // Step 3: Force a new window via Cmd+N if no window exists.
        // On macOS 26, the WindowGroup may not create a window on first launch
        // under XCUITest, especially after terminate(). Retry Cmd+N up to 3
        // times with increasing delays to handle Liquid Glass timing variance.
        #if os(macOS)
        for attempt in 1...3 where app.windows.count == 0 {
            print("[LAUNCH] No window found (attempt \(attempt)/3) — sending Cmd+N...")
            app.typeKey("n", modifierFlags: .command)
            sleep(UInt32(1 + attempt)) // 2s, 3s, 4s — increasing delays
        }
        #endif

        // Step 4: Verify window exists now
        if app.windows.count > 0 {
            let window = app.windows.firstMatch
            print("[LAUNCH] ✅ Window found! frame=\(window.frame)")
            print("[LAUNCH] Buttons: \(app.buttons.count), StaticTexts: \(app.staticTexts.count)")
        } else {
            print("[LAUNCH] ⚠️ Still no window after Cmd+N")
            print("[LAUNCH] Descendants: \(app.descendants(matching: .any).count)")
        }

        return app
    }

    // MARK: - Flow-Driven Tests
    //
    // These tests delegate to FlowDrivenUITestRunner, executing test scenarios
    // from JSON flow definitions in automation/flows/ui/.
    //
    // Path 1 (in-app): AutomationFlowRunner + AccessibilityTreeInspector
    // Path 2 (XCUITest — THIS): FlowDrivenUITestRunner + XCUIElement queries

    func testFlowBasicNavigation() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_basic_navigation_flow")
        try runner.execute()
    }

    func testFlowSettingsInteractions() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_settings_flow")
        try runner.execute()
    }

    func testFlowSidebarStructure() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_sidebar_flow")
        try runner.execute()
    }

    func testFlowInputAreaComponents() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_input_area_flow")
        try runner.execute()
    }

    func testFlowChatInteractions() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_chat_interactions_flow")
        try runner.execute()
    }

    func testFlowQuickActions() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_quick_actions_flow")
        try runner.execute()
    }

    func testFlowMCPServerManagement() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_mcp_server_flow")
        try runner.execute()
    }

    func testFlowMenuCommands() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_menu_commands_flow")
        try runner.execute()
    }

    func testFlowURLImport() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_url_import_flow")
        try runner.execute()
    }

    func testFlowCommunityBrowser() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_community_browser_flow")
        try runner.execute()
    }

    func testFlowEvalExecution() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_eval_execution_flow")
        try runner.execute()
    }

    func testFlowNavigationEfficiency() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_navigation_efficiency_flow")
        try runner.execute()
    }

    func testFlowSettingsPersistence() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_settings_persistence_flow")
        try runner.execute()
    }

    func testFlowToolCalling() throws {
        let app = launchApp()
        let runner = FlowDrivenUITestRunner(app: app, flowName: "macos_tool_calling_flow")
        try runner.execute()
    }
}
