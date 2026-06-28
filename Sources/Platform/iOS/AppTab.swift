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

/// Type-safe tab identifiers for the iOS TabView.
///
/// Replaces fragile Int-based `.tag()` values with a Hashable enum
/// that can be used with `TabView(selection:)` and tested in isolation.
///
/// Accessibility: Each case maps to a human-readable label for VoiceOver.
enum AppTab: String, Hashable, CaseIterable, Sendable {
    case models
    case chat
    case evaluations
    case lab
    case settings
}
#endif
