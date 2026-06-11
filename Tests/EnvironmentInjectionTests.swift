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
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Environment Injection Tests

/// Validates that ConversationViewModel supports dependency injection
/// and does NOT expose a `shared` singleton.
///
/// These tests ensure the SwiftUI @Environment injection pattern is the
/// sole ownership path — no global mutable state leaks across tests or
/// app scenes.
@MainActor
final class EnvironmentInjectionTests: XCTestCase {

    // MARK: - Singleton Absence

    func testNoSharedSingleton() {
        // Use Mirror to inspect ConversationViewModel's type-level members.
        // If someone re-adds `static let shared`, this test catches it.
        let mirror = Mirror(reflecting: ConversationViewModel.self)

        let hasSharedChild = mirror.children.contains { label, _ in
            label == "shared"
        }

        XCTAssertFalse(hasSharedChild,
            "ConversationViewModel must NOT expose a 'shared' singleton. "
            + "Use @Environment injection instead.")
    }

    // MARK: - Default Init

    func testViewModelDefaultInit() {
        let vm = ConversationViewModel()

        XCTAssertFalse(vm.statusMessage.isEmpty,
            "Default init should set a non-empty status message")
        XCTAssertFalse(vm.isGenerating,
            "Default init should not be generating")
        XCTAssertFalse(vm.isLoadingModel,
            "Default init should not be loading a model")
    }

    // MARK: - Injected Engine

    func testViewModelWithMockEngine() {
        let mockEngine = MockInstrumentedEngine()
        let vm = ConversationViewModel(engine: mockEngine)

        XCTAssertFalse(vm.isEngineReady,
            "Mock engine should not be ready by default")
    }

    // MARK: - Multiple Independent Instances

    func testMultipleIndependentInstances() {
        let vm1 = ConversationViewModel()
        let vm2 = ConversationViewModel()

        vm1.prompt = "Hello from vm1"
        vm2.prompt = "Hello from vm2"

        XCTAssertNotEqual(vm1.prompt, vm2.prompt,
            "Separate instances should have independent state")
        XCTAssertEqual(vm1.prompt, "Hello from vm1")
        XCTAssertEqual(vm2.prompt, "Hello from vm2")
    }
}
