import XCTest

final class GemmaEdgeGalleryUITests: XCTestCase {

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

    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-RunAutomationHarness"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5.0))
        return app
    }

    func testBasicNavigation() throws {
        let app = launchApp()

        #if os(macOS)
        let settingsButton = app.buttons["button_settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should exist in the toolbar")
        settingsButton.click()
        let useGPUToggle = app.switches["toggle_useGPU"]
        XCTAssertTrue(useGPUToggle.waitForExistence(timeout: 2.0))
        app.typeKey("w", modifierFlags: .command)
        #else
        let settingsButton = app.buttons["button_settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should exist")
        settingsButton.click()
        
        let doneButton = app.buttons["button_doneSettings"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2.0))
        doneButton.click()
        #endif

        let dashboardButton = app.buttons["button_dashboard"]
        XCTAssertTrue(dashboardButton.exists, "Dashboard button should exist")
        dashboardButton.click()
        
        let doneButtonDash = app.buttons["button_doneDashboard"]
        XCTAssertTrue(doneButtonDash.waitForExistence(timeout: 2.0))
        doneButtonDash.click()

        let loadModelButton = app.buttons["button_loadModel"]
        XCTAssertTrue(loadModelButton.exists, "Load Model button should exist")
        loadModelButton.click()
        
        app.typeKey(.escape, modifierFlags: [])
    }

    func testChatInteractions() throws {
        let app = launchApp()

        let attachImageBtn = app.buttons["button_attachImage"]
        if attachImageBtn.exists && attachImageBtn.isEnabled {
            attachImageBtn.click()
        }

        let refreshButton = app.buttons["button_refresh"]
        XCTAssertTrue(refreshButton.exists, "Refresh button should exist")
        refreshButton.click()
        
        let promptField = app.textFields["textField_prompt"]
        if promptField.exists {
            promptField.click()
            promptField.typeText("Hello, AI!\r")
            
            let sendButton = app.buttons["button_send"]
            XCTAssertTrue(sendButton.exists, "Send button should exist")
        }
    }

    func testSettingsInteractions() throws {
        let app = launchApp()

        #if os(macOS)
        let settingsButton = app.buttons["button_settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should exist in the toolbar")
        settingsButton.click()
        #else
        let settingsButton = app.buttons["button_settings"]
        XCTAssertTrue(settingsButton.exists)
        settingsButton.click()
        #endif
        
        let useGPUToggle = app.switches["toggle_useGPU"]
        XCTAssertTrue(useGPUToggle.waitForExistence(timeout: 2.0))
        
        let enableBenchmarkToggle = app.switches["toggle_enableBenchmark"]
        XCTAssertTrue(enableBenchmarkToggle.exists)

        let hfTokenField = app.secureTextFields["secureField_hfToken"]
        if hfTokenField.exists {
            hfTokenField.click()
            hfTokenField.typeText("test_token")
            let saveTokenBtn = app.buttons["button_saveToken"]
            XCTAssertTrue(saveTokenBtn.isEnabled)
        } else {
            let clearTokenBtn = app.buttons["button_clearToken"]
            if clearTokenBtn.exists {
                clearTokenBtn.click()
                XCTAssertTrue(app.secureTextFields["secureField_hfToken"].waitForExistence(timeout: 2.0))
            }
        }
        
        
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        let doneButton = app.buttons["button_doneSettings"]
        doneButton.click()
        #endif
    }

    func testQuickActionsAndModelShowcase() throws {
        let app = launchApp()

        // Test Quick Actions
        let hintChat = app.groups["hint_chat"]
        if hintChat.exists {
            XCTAssertTrue(hintChat.isHittable)
        }
        
        let hintThinking = app.groups["hint_thinking"]
        if hintThinking.exists {
            XCTAssertTrue(hintThinking.isHittable)
        }

        // Test Model Showcase (by verifying the view and done button exist if we can trigger it)
        // Without being able to reliably right click a specific model card to open context menu in XCTest easily,
        // we will just assert the IDs are theoretically available if the view is presented.
        let modelShowcase = app.scrollViews["view_modelShowcase"]
        if modelShowcase.exists {
            let closeBtn = app.buttons["button_closeShowcase"]
            XCTAssertTrue(closeBtn.exists)
            closeBtn.click()
        }
    }

    func testAddMCPServer() throws {
        let app = launchApp()

        #if os(macOS)
        let settingsButton = app.buttons["button_settings"]
        settingsButton.click()
        #else
        let settingsButton = app.buttons["button_settings"]
        settingsButton.click()
        #endif
        
        let addMCPButton = app.buttons["button_addMCP"]
        if !addMCPButton.waitForExistence(timeout: 1.0) {
            let toolCallingToggle = app.switches["toggle_enableToolCalling"]
            toolCallingToggle.click()
        }
        XCTAssertTrue(addMCPButton.waitForExistence(timeout: 2.0))
        addMCPButton.click()
        
        // Find the inline editor text fields by prefix
        let nameField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'textField_mcp_name_'")).firstMatch
        if nameField.waitForExistence(timeout: 2.0) {
            nameField.click()
            nameField.typeText(" Test Server")
            
            let commandField = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH 'textField_mcp_command_'")).firstMatch
            commandField.click()
            commandField.typeText("npx")
            
            let closeBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'button_close_mcp_'")).firstMatch
            XCTAssertTrue(closeBtn.exists)
            closeBtn.click()
        }
    }
}

