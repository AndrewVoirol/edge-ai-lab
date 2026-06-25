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

import XCTest

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for the Onboarding / First-Run Experience.
/// Validates OnboardingManager's UserDefaults-backed state and OnboardingPage data model.
@MainActor
final class OnboardingTests: XCTestCase {

    /// Creates a fresh, isolated UserDefaults suite for each test to avoid pollution.
    private func freshDefaults() -> UserDefaults {
        let suiteName = "com.test.onboarding.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    // MARK: - OnboardingManager State Tests

    func testOnboardingDefaultsToNotCompleted() {
        let defaults = freshDefaults()
        let manager = OnboardingManager(defaults: defaults)
        XCTAssertFalse(
            manager.hasCompletedOnboarding,
            "Fresh UserDefaults should report onboarding as not completed"
        )
    }

    func testMarkingOnboardingCompleted() {
        let defaults = freshDefaults()
        let manager = OnboardingManager(defaults: defaults)

        // Pre-condition
        XCTAssertFalse(manager.hasCompletedOnboarding)

        // Act
        manager.hasCompletedOnboarding = true

        // Assert
        XCTAssertTrue(
            manager.hasCompletedOnboarding,
            "After marking completed, getter should return true"
        )

        // Verify persistence — a new manager reading the same defaults should agree
        let manager2 = OnboardingManager(defaults: defaults)
        XCTAssertTrue(
            manager2.hasCompletedOnboarding,
            "A second manager reading the same defaults should see completed = true"
        )
    }

    // MARK: - OnboardingPage Data Model Tests

    func testOnboardingPagesHaveCorrectCount() {
        let pages = OnboardingPage.allPages
        XCTAssertEqual(pages.count, 4, "There should be exactly 4 onboarding pages")
    }

    func testOnboardingPagesHaveTitlesAndDescriptions() {
        let pages = OnboardingPage.allPages
        for (index, page) in pages.enumerated() {
            XCTAssertFalse(
                page.title.isEmpty,
                "Page \(index) should have a non-empty title"
            )
            XCTAssertFalse(
                page.subtitle.isEmpty,
                "Page \(index) should have a non-empty subtitle"
            )
            XCTAssertFalse(
                page.iconName.isEmpty,
                "Page \(index) should have a non-empty icon name"
            )
        }
    }
}
