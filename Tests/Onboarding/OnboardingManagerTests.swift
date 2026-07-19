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

import Testing
import Foundation
#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - OnboardingManager Tests

@Suite("OnboardingManager")
struct OnboardingManagerTests {

    /// Creates an isolated UserDefaults suite and returns both the suite and its name.
    /// The caller must clean up with `removePersistentDomain(forName:)` after use.
    private static func makeIsolatedDefaults(
        tag: String = #function
    ) -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "com.edgeailab.test.onboarding.\(tag).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test("Fresh UserDefaults returns false for hasCompletedOnboarding")
    func freshDefaultsReturnsFalse() {
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let manager = OnboardingManager(defaults: defaults)

        #expect(manager.hasCompletedOnboarding == false)
    }

    @Test("Setting hasCompletedOnboarding to true persists")
    func settingTruePersists() {
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let manager = OnboardingManager(defaults: defaults)
        manager.hasCompletedOnboarding = true

        #expect(manager.hasCompletedOnboarding == true)
        // Verify via a fresh manager reading the same suite
        let secondManager = OnboardingManager(defaults: defaults)
        #expect(secondManager.hasCompletedOnboarding == true)
    }

    @Test("Setting hasCompletedOnboarding back to false works")
    func settingBackToFalse() {
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let manager = OnboardingManager(defaults: defaults)
        manager.hasCompletedOnboarding = true
        #expect(manager.hasCompletedOnboarding == true)

        manager.hasCompletedOnboarding = false
        #expect(manager.hasCompletedOnboarding == false)
    }

    @Test("Multiple managers sharing same UserDefaults suite see same state")
    func sharedSuiteSameState() {
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let managerA = OnboardingManager(defaults: defaults)
        let managerB = OnboardingManager(defaults: defaults)

        #expect(managerA.hasCompletedOnboarding == false)
        #expect(managerB.hasCompletedOnboarding == false)

        managerA.hasCompletedOnboarding = true

        #expect(managerA.hasCompletedOnboarding == true)
        #expect(managerB.hasCompletedOnboarding == true)
    }

    @Test("Independent UserDefaults suites are isolated from each other")
    func independentSuitesIsolated() {
        let (defaultsA, suiteNameA) = Self.makeIsolatedDefaults(tag: "suiteA")
        let (defaultsB, suiteNameB) = Self.makeIsolatedDefaults(tag: "suiteB")
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteNameA)
            UserDefaults.standard.removePersistentDomain(forName: suiteNameB)
        }

        let managerA = OnboardingManager(defaults: defaultsA)
        let managerB = OnboardingManager(defaults: defaultsB)

        managerA.hasCompletedOnboarding = true

        #expect(managerA.hasCompletedOnboarding == true)
        #expect(managerB.hasCompletedOnboarding == false,
                "Changing suite A must not affect suite B")
    }
}

// MARK: - OnboardingPage Tests

@Suite("OnboardingPage")
struct OnboardingPageTests {

    @Test("allPages has exactly 4 pages")
    func allPagesCount() {
        #expect(OnboardingPage.allPages.count == 4)
    }

    @Test("First page title is 'Welcome to Edge AI Lab'")
    func firstPageTitle() {
        let firstPage = OnboardingPage.allPages[0]
        #expect(firstPage.title == "Welcome to Edge AI Lab")
    }

    @Test("Each page has a non-empty iconName, title, and subtitle")
    func allPagesHaveNonEmptyFields() {
        for page in OnboardingPage.allPages {
            #expect(!page.iconName.isEmpty,
                    "Page '\(page.title)' should have a non-empty iconName")
            #expect(!page.title.isEmpty,
                    "Page with icon '\(page.iconName)' should have a non-empty title")
            #expect(!page.subtitle.isEmpty,
                    "Page '\(page.title)' should have a non-empty subtitle")
        }
    }

    @Test("Each page has a unique ID")
    func allPagesHaveUniqueIDs() {
        let ids = OnboardingPage.allPages.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count,
                "All page IDs should be unique")
    }

    @Test("Each page iconName is a non-empty SF Symbol name pattern")
    func iconNamesAreNonEmpty() {
        for page in OnboardingPage.allPages {
            #expect(!page.iconName.isEmpty,
                    "Page '\(page.title)' should have a non-empty iconName")
            // SF Symbol names use lowercase letters, dots, and periods — just verify non-empty string
            #expect(page.iconName.count > 1,
                    "SF Symbol names are typically multi-character: '\(page.iconName)'")
        }
    }

    @Test("Pages are in expected order: Welcome, Model Hub, Conversations, Benchmark")
    func pagesInExpectedOrder() {
        let pages = OnboardingPage.allPages
        #expect(pages.count == 4)

        #expect(pages[0].title == "Welcome to Edge AI Lab")
        #expect(pages[1].title == "Your Model Hub")
        #expect(pages[2].title == "Run Experiments")
        #expect(pages[3].title == "Benchmark & Evaluate")
    }
}
