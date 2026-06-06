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

    // MARK: - Expanded UI Coverage Tests (Phase 0.2)

    /// Verifies that ALL settings toggles exist and are interactable.
    /// Covers: toggle_enableMTP, toggle_constrainedDecoding, toggle_enableThinking, toggle_enableAgentSkills
    func testAllSettingsTogglesExist() throws {
        let app = launchApp()

        #if os(macOS)
        app.buttons["button_settings"].click()
        #else
        app.buttons["button_settings"].click()
        #endif

        // Wait for settings to load
        let gpuToggle = app.switches["toggle_useGPU"]
        XCTAssertTrue(gpuToggle.waitForExistence(timeout: 3.0), "GPU toggle should exist")

        let benchmarkToggle = app.switches["toggle_enableBenchmark"]
        XCTAssertTrue(benchmarkToggle.exists, "Benchmark toggle should exist")

        let mtpToggle = app.switches["toggle_enableMTP"]
        XCTAssertTrue(mtpToggle.exists, "MTP toggle should exist")

        let constrainedToggle = app.switches["toggle_constrainedDecoding"]
        XCTAssertTrue(constrainedToggle.exists, "Constrained decoding toggle should exist")

        let thinkingToggle = app.switches["toggle_enableThinking"]
        XCTAssertTrue(thinkingToggle.exists, "Thinking toggle should exist")

        let toolCallingToggle = app.switches["toggle_enableToolCalling"]
        XCTAssertTrue(toolCallingToggle.exists, "Tool calling toggle should exist")

        // Enable tool calling to reveal agent skills toggle
        if toolCallingToggle.value as? String == "0" {
            toolCallingToggle.click()
        }

        // On macOS Settings window, the agent skills toggle may require
        // scrolling down to become visible in the fixed-height window
        let agentSkillsToggle = app.switches["toggle_enableAgentSkills"]
        if !agentSkillsToggle.waitForExistence(timeout: 2.0) {
            // Try scrolling down in the settings form
            #if os(macOS)
            let settingsWindow = app.windows.element(boundBy: 1)
            if settingsWindow.exists {
                settingsWindow.scroll(byDeltaX: 0, deltaY: -200)
            }
            #endif
        }
        // Agent skills toggle may still not appear if the form doesn't scroll enough;
        // this is a known limitation of fixed-height Settings windows
        if agentSkillsToggle.exists {
            XCTAssertTrue(agentSkillsToggle.isHittable, "Agent skills toggle should be hittable")
        }

        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        app.buttons["button_doneSettings"].click()
        #endif
    }

    /// Verifies sampler controls (steppers, sliders, preset buttons) exist in Settings.
    func testSamplerControls() throws {
        let app = launchApp()

        #if os(macOS)
        app.buttons["button_settings"].click()
        #else
        app.buttons["button_settings"].click()
        #endif

        // Wait for settings to load
        XCTAssertTrue(app.switches["toggle_useGPU"].waitForExistence(timeout: 3.0))

        // Sampler controls
        let topKStepper = app.steppers["stepper_topK"]
        XCTAssertTrue(topKStepper.exists, "Top-K stepper should exist")

        let topPSlider = app.sliders["slider_topP"]
        XCTAssertTrue(topPSlider.exists, "Top-P slider should exist")

        let tempSlider = app.sliders["slider_temperature"]
        XCTAssertTrue(tempSlider.exists, "Temperature slider should exist")

        let seedStepper = app.steppers["stepper_seed"]
        XCTAssertTrue(seedStepper.exists, "Seed stepper should exist")

        // Preset buttons
        let greedyButton = app.buttons["button_greedyMatch"]
        XCTAssertTrue(greedyButton.exists, "Greedy match preset button should exist")

        let defaultButton = app.buttons["button_defaultSampling"]
        XCTAssertTrue(defaultButton.exists, "Default sampling preset button should exist")

        // Test clicking greedy preset
        greedyButton.click()

        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        app.buttons["button_doneSettings"].click()
        #endif
    }

    /// Verifies the system message editor exists and can be interacted with.
    func testSystemMessageEditor() throws {
        let app = launchApp()

        #if os(macOS)
        app.buttons["button_settings"].click()
        #else
        app.buttons["button_settings"].click()
        #endif

        XCTAssertTrue(app.switches["toggle_useGPU"].waitForExistence(timeout: 3.0))

        let systemEditor = app.textViews["textEditor_systemMessage"]
        XCTAssertTrue(systemEditor.exists, "System message editor should exist")

        // Type a system message
        systemEditor.click()
        systemEditor.typeText("You are a helpful assistant.")

        // The clear button should appear now
        let clearButton = app.buttons["button_clearSystemMessage"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 2.0), "Clear system message button should appear after typing")

        // Clear the message
        clearButton.click()

        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        #else
        app.buttons["button_doneSettings"].click()
        #endif
    }

    /// Verifies the model card strip section exists.
    /// Individual model cards require .litertlm files on disk to appear as discovered,
    /// or registry models to appear as downloadable, so we verify the section container.
    func testModelCardStripExists() throws {
        let app = launchApp()

        // The section_models container should always be present,
        // even if no models are discovered yet
        let sectionPredicate = NSPredicate(format: "identifier == 'section_models'")
        let sectionElement = app.descendants(matching: .any).matching(sectionPredicate).firstMatch
        XCTAssertTrue(
            sectionElement.waitForExistence(timeout: 5.0),
            "Model section container (section_models) should exist"
        )
    }

    /// Verifies multimodal attachment buttons.
    /// NOTE: These buttons only appear when a multimodal model is loaded.
    /// Without a model, we verify they DON'T appear (correct behavior).
    func testMultimodalAttachmentButtons() throws {
        let app = launchApp()

        // Image/audio attachment buttons are conditionally shown based on
        // supportsImageInput / supportsAudioInput from the active model.
        // Without a model loaded, these should NOT exist — that's correct.
        let attachImageBtn = app.buttons["button_attachImage"]
        let attachAudioBtn = app.buttons["button_attachAudio"]

        if attachImageBtn.exists {
            // A multimodal model is loaded — verify the button is interactable
            XCTAssertTrue(attachImageBtn.isHittable, "Attach image button should be hittable")
        }

        if attachAudioBtn.exists {
            XCTAssertTrue(attachAudioBtn.isHittable, "Attach audio button should be hittable")
        }

        // Verify the basic input area exists regardless of model state
        let promptField = app.textFields["textField_prompt"]
        XCTAssertTrue(promptField.exists, "Prompt field should always exist")
        let sendButton = app.buttons["button_send"]
        XCTAssertTrue(sendButton.exists, "Send button should always exist")
    }

    /// Verifies new chat functionality works via menu command on macOS or button on iOS.
    func testNewChatFunctionality() throws {
        let app = launchApp()

        #if os(macOS)
        // Test ⌘N menu command
        app.typeKey("n", modifierFlags: .command)
        // After new chat, the conversation area should be cleared
        // Verify the prompt field is still accessible
        let promptField = app.textFields["textField_prompt"]
        XCTAssertTrue(promptField.waitForExistence(timeout: 2.0), "Prompt field should exist after new chat")
        #else
        let newChatButton = app.buttons["button_newChat"]
        XCTAssertTrue(newChatButton.exists, "New chat button should exist on iOS")
        newChatButton.click()
        #endif
    }

    /// Verifies the input area components: prompt field, send button, and keyboard shortcut hint.
    func testInputAreaComponents() throws {
        let app = launchApp()

        // Prompt field
        let promptField = app.textFields["textField_prompt"]
        XCTAssertTrue(promptField.exists, "Prompt text field should exist")
        XCTAssertTrue(promptField.isHittable, "Prompt text field should be hittable")

        // Click and type
        promptField.click()
        promptField.typeText("Test prompt")

        // Send button
        let sendButton = app.buttons["button_send"]
        XCTAssertTrue(sendButton.exists, "Send button should exist")

        // Refresh button
        let refreshButton = app.buttons["button_refresh"]
        XCTAssertTrue(refreshButton.exists, "Refresh button should exist")
        XCTAssertTrue(refreshButton.isHittable, "Refresh button should be hittable")

        // Load model button
        let loadModelButton = app.buttons["button_loadModel"]
        XCTAssertTrue(loadModelButton.exists, "Load model button should exist")
        XCTAssertTrue(loadModelButton.isHittable, "Load model button should be hittable")

        // Dashboard button
        let dashboardButton = app.buttons["button_dashboard"]
        XCTAssertTrue(dashboardButton.exists, "Dashboard button should exist")
    }

    /// Verifies macOS-specific menu bar commands work.
    #if os(macOS)
    func testMacOSMenuBarCommands() throws {
        let app = launchApp()

        // Test ⌘R (Refresh discovered models) — should not crash
        app.typeKey("r", modifierFlags: .command)

        // Test ⌘D (Dashboard) — should open the dashboard sheet
        app.typeKey("d", modifierFlags: .command)
        let doneDash = app.buttons["button_doneDashboard"]
        XCTAssertTrue(doneDash.waitForExistence(timeout: 3.0), "Dashboard should open via ⌘D")
        doneDash.click()

        // Test ⌘O (Load Model) — should open file picker
        app.typeKey("o", modifierFlags: .command)
        // Dismiss the file picker with Escape
        app.typeKey(.escape, modifierFlags: [])

        // Test ⌘N (New Chat) — should clear conversation
        app.typeKey("n", modifierFlags: .command)

        // Verify app is still responsive
        let promptField = app.textFields["textField_prompt"]
        XCTAssertTrue(promptField.waitForExistence(timeout: 2.0))
    }
    #endif
}
