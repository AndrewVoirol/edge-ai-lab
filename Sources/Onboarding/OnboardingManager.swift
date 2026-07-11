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

import Foundation

// MARK: - Onboarding Manager

/// Manages the onboarding / first-run experience completion state.
/// Backed by UserDefaults for persistence across launches.
///
/// Accepts a custom `UserDefaults` instance for testability — tests inject
/// isolated suites to avoid cross-test pollution.
class OnboardingManager {
    private let defaults: UserDefaults
    private static let key = "hasCompletedOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Whether the user has completed the onboarding flow.
    /// Reads `false` on a fresh install (UserDefaults default for missing Bool keys).
    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Self.key) }
        set { defaults.set(newValue, forKey: Self.key) }
    }
}

// MARK: - Onboarding Page Model

/// Data model for a single page in the onboarding carousel.
struct OnboardingPage: Identifiable {
    let id = UUID()
    let iconName: String
    let title: String
    let subtitle: String

    /// The four pages of the onboarding flow.
    static let allPages: [OnboardingPage] = [
        OnboardingPage(
            iconName: "brain.head.profile",
            title: "Welcome to Edge AI Lab",
            subtitle: "Run powerful AI models privately on your device"
        ),
        OnboardingPage(
            iconName: "arrow.down.circle",
            title: "Your Model Hub",
            subtitle: "Download, manage, and run models from HuggingFace and Kaggle"
        ),
        OnboardingPage(
            iconName: "bubble.left.and.text.bubble.right",
            title: "Run Experiments",
            subtitle: "Test AI with text, images, and audio — all on-device"
        ),
        OnboardingPage(
            iconName: "chart.bar.xaxis.ascending",
            title: "Benchmark & Evaluate",
            subtitle: "Run evaluation suites and compare model performance"
        ),
    ]
}
