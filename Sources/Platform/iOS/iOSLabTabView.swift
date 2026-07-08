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

#if os(iOS)
import SwiftUI

// MARK: - iOS Lab Tab View

/// The "Lab" tab on iOS, hosting the Performance Dashboard for benchmarks.
///
/// This view provides iOS users with access to the same `PerformanceDashboardView`
/// that macOS users access through the sidebar's "Benchmarks > Dashboard" section.
///
/// Wrapped in a `NavigationStack` for proper title display and potential
/// future drill-down navigation (e.g., individual benchmark run details).
///
/// Accessibility: All interactive elements inherit identifiers from
/// `PerformanceDashboardView` itself.
struct iOSLabTabView: View {

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)

                PerformanceDashboardView()
            }
            .navigationTitle("Lab")
            .navigationBarTitleDisplayMode(.large)
        }
        .accessibilityIdentifier("tab_lab")
    }
}
#endif

