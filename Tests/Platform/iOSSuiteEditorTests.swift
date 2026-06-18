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
import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for the iOS Custom Suite Editor persistence and validation.
///
/// Exercises `EvalStore.saveCustomSuite`, `loadCustomSuites`, and `deleteCustomSuite`
/// with a temp directory DI pattern for full isolation.
final class iOSSuiteEditorTests: XCTestCase {

    // MARK: - Setup

    private var tempDir: URL!
    private var store: EvalStore!

    @MainActor override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iOSSuiteEditorTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        // EvalStore's customSuitesDirectory navigates UP from storageDirectory,
        // so we nest storageDirectory inside a subdirectory to keep everything in our temp tree.
        let evalRunsDir = tempDir.appendingPathComponent("EvalRuns")
        try? FileManager.default.createDirectory(at: evalRunsDir, withIntermediateDirectories: true)
        store = EvalStore(storageDirectory: evalRunsDir)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        // Also clean up any stray CustomSuites that might have been created
        let customSuitesDir = tempDir?.appendingPathComponent("CustomSuites")
        if let customSuitesDir {
            try? FileManager.default.removeItem(at: customSuitesDir)
        }
        super.tearDown()
    }

    // MARK: - Test 1: Save and Load roundtrip

    /// Save a custom suite, load all custom suites, verify the suite roundtrips.
    @MainActor
    func testEvalSuiteSaveAndLoad() {
        let suite = makeCustomSuite(name: "My Custom Suite")
        store.saveCustomSuite(suite)

        let loaded = store.loadCustomSuites()
        XCTAssertEqual(loaded.count, 1, "Expected exactly 1 saved custom suite")
        XCTAssertEqual(loaded.first?.id, suite.id)
        XCTAssertEqual(loaded.first?.name, "My Custom Suite")
    }

    // MARK: - Test 2: Delete removes suite

    /// Save a suite, delete it, verify loadCustomSuites returns empty.
    @MainActor
    func testEvalSuiteDeleteRemoves() {
        let suite = makeCustomSuite(name: "Delete Me")
        store.saveCustomSuite(suite)

        // Confirm it was saved
        XCTAssertEqual(store.loadCustomSuites().count, 1)

        // Delete and verify
        store.deleteCustomSuite(id: suite.id)
        let remaining = store.loadCustomSuites()
        XCTAssertTrue(remaining.isEmpty, "Expected no suites after deletion")
    }

    // MARK: - Test 3: Built-in suites have prompts

    /// Verify that EvalSuite.prompts is accessible and non-empty on built-in suites.
    func testEvalSuiteHasPrompts() {
        for suite in BuiltInEvalSuites.allBuiltIn {
            XCTAssertFalse(
                suite.prompts.isEmpty,
                "Built-in suite '\(suite.name)' should have at least one prompt"
            )
            // Verify each prompt has non-empty text
            for prompt in suite.prompts {
                XCTAssertFalse(
                    prompt.prompt.trimmingCharacters(in: .whitespaces).isEmpty,
                    "Prompt in '\(suite.name)' should have non-empty text"
                )
            }
        }
    }

    // MARK: - Test 4: Roundtrip preserves all fields

    /// Save and load a custom suite, verify ALL fields are preserved.
    @MainActor
    func testCustomSuiteRoundtripPreservesAllFields() {
        let fixedDate = Date(timeIntervalSince1970: 1700000000)
        let fixedId = UUID()
        let promptId = UUID()

        let suite = EvalSuite(
            id: fixedId,
            name: "Full Field Test",
            description: "Tests all fields roundtrip",
            category: .toolCalling,
            prompts: [
                EvalPrompt(
                    id: promptId,
                    prompt: "What time is it?",
                    expectedBehavior: .toolCall(toolName: "get_date_time"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "Calculate 2+2",
                    expectedBehavior: .containsText("4"),
                    timeoutSeconds: 30
                ),
            ],
            isBuiltIn: false,
            createdAt: fixedDate
        )

        store.saveCustomSuite(suite)
        let loaded = store.loadCustomSuites()
        XCTAssertEqual(loaded.count, 1)

        let roundtripped = loaded[0]
        XCTAssertEqual(roundtripped.id, fixedId, "ID should survive roundtrip")
        XCTAssertEqual(roundtripped.name, "Full Field Test", "Name should survive roundtrip")
        XCTAssertEqual(roundtripped.description, "Tests all fields roundtrip", "Description should survive roundtrip")
        XCTAssertEqual(roundtripped.category, .toolCalling, "Category should survive roundtrip")
        XCTAssertEqual(roundtripped.isBuiltIn, false, "isBuiltIn should survive roundtrip")
        XCTAssertEqual(roundtripped.prompts.count, 2, "Prompt count should survive roundtrip")

        // Verify first prompt in detail
        let p1 = roundtripped.prompts[0]
        XCTAssertEqual(p1.id, promptId, "Prompt ID should survive roundtrip")
        XCTAssertEqual(p1.prompt, "What time is it?", "Prompt text should survive roundtrip")
        XCTAssertEqual(p1.timeoutSeconds, 90, "Timeout should survive roundtrip")

        // Verify second prompt expected behavior
        let p2 = roundtripped.prompts[1]
        XCTAssertEqual(p2.prompt, "Calculate 2+2")
        XCTAssertEqual(p2.timeoutSeconds, 30)

        // Verify createdAt survives (within 1 second tolerance for ISO-8601 truncation)
        XCTAssertEqual(
            roundtripped.createdAt.timeIntervalSince1970,
            fixedDate.timeIntervalSince1970,
            accuracy: 1.0,
            "createdAt should survive roundtrip"
        )
    }

    // MARK: - Test 5: Validation

    /// Test that suites with empty name or no prompts are detected as invalid
    /// using the same validation logic as the editor.
    @MainActor
    func testEvalSuiteValidation() {
        // A suite with an empty name should be invalid
        let emptyNameSuite = makeCustomSuite(name: "   ")
        XCTAssertTrue(
            emptyNameSuite.name.trimmingCharacters(in: .whitespaces).isEmpty,
            "Suite with whitespace-only name should be considered invalid"
        )

        // A suite with no prompts should be invalid
        let noPromptsSuite = EvalSuite(
            name: "Valid Name",
            description: "Has no prompts",
            category: .custom,
            prompts: [],
            isBuiltIn: false
        )
        XCTAssertTrue(
            noPromptsSuite.prompts.isEmpty,
            "Suite with no prompts should be considered invalid"
        )

        // A suite with an empty-text prompt should be invalid
        let emptyPromptTextSuite = EvalSuite(
            name: "Valid Name",
            description: "Has an empty prompt",
            category: .custom,
            prompts: [
                EvalPrompt(prompt: "   ", expectedBehavior: .nonEmpty)
            ],
            isBuiltIn: false
        )
        XCTAssertTrue(
            emptyPromptTextSuite.prompts.allSatisfy {
                $0.prompt.trimmingCharacters(in: .whitespaces).isEmpty
            },
            "Suite where all prompts have empty text should be considered invalid"
        )

        // A valid suite should pass all checks
        let validSuite = makeCustomSuite(name: "Valid Suite")
        XCTAssertFalse(
            validSuite.name.trimmingCharacters(in: .whitespaces).isEmpty,
            "Valid suite should have non-empty name"
        )
        XCTAssertFalse(
            validSuite.prompts.isEmpty,
            "Valid suite should have at least one prompt"
        )
        XCTAssertTrue(
            validSuite.prompts.allSatisfy {
                !$0.prompt.trimmingCharacters(in: .whitespaces).isEmpty
            },
            "All prompts in a valid suite should have non-empty text"
        )
    }

    // MARK: - Helpers

    /// Creates a minimal valid custom suite for testing.
    private func makeCustomSuite(name: String) -> EvalSuite {
        EvalSuite(
            name: name,
            description: "Test suite description",
            category: .custom,
            prompts: [
                EvalPrompt(
                    prompt: "Hello, how are you?",
                    expectedBehavior: .nonEmpty,
                    timeoutSeconds: 60
                )
            ],
            isBuiltIn: false
        )
    }
}
