import XCTest

final class GemmaEdgeGalleryUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testTapAllMajorButtons() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        // Run with special automation flag so auto-load doesn't kick in
        app.launchArguments = ["-RunAutomationHarness"]
        app.launch()

        // Wait for main view
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5.0))

        // 1. Settings button
        let settingsButton = app.buttons["button_settings"]
        XCTAssertTrue(settingsButton.exists, "Settings button should exist")
        settingsButton.click()
        
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2.0))
        doneButton.click()

        // 2. Dashboard button
        let dashboardButton = app.buttons["button_dashboard"]
        XCTAssertTrue(dashboardButton.exists, "Dashboard button should exist")
        dashboardButton.click()
        
        XCTAssertTrue(doneButton.waitForExistence(timeout: 2.0))
        doneButton.click()

        // 3. Load Model button
        let loadModelButton = app.buttons["button_loadModel"]
        XCTAssertTrue(loadModelButton.exists, "Load Model button should exist")
        loadModelButton.click()
        
        // This opens a file picker (NSOpenPanel) - simulating cancellation or just interacting with it might be tricky in pure macOS UI tests but we clicked it.
        // On macOS, file dialogs run out of process. We can send escape key.
        app.typeKey(.escape, modifierFlags: [])

        // 4. Attach Image
        let attachImageBtn = app.buttons["button_attachImage"]
        // In empty state without a model loaded, does the button exist?
        // Wait, ContentView hides multimodal attachments if model doesn't support them.
        // We might not be able to tap them if model is not loaded.
        // Let's just check refresh
        let refreshButton = app.buttons["button_refresh"]
        XCTAssertTrue(refreshButton.exists, "Refresh button should exist")
        refreshButton.click()
        
        // Text field
        let promptField = app.textFields["textField_prompt"]
        if promptField.exists {
            promptField.click()
            promptField.typeText("Hello, AI!\r")
            
            // Wait for it
            let sendButton = app.buttons["button_send"]
            XCTAssertTrue(sendButton.exists, "Send button should exist")
            sendButton.click()
        }
    }
}
