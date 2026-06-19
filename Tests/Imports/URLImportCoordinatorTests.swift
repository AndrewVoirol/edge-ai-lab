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

// MARK: - URLImportCoordinator Tests

@Suite("URLImportCoordinator")
@MainActor
struct URLImportCoordinatorTests {

    // MARK: - Initial State

    @Suite("Initial State")
    @MainActor
    struct InitialState {

        @Test("importManager is nil on fresh coordinator")
        func importManagerIsNilByDefault() {
            let coordinator = URLImportCoordinator()
            #expect(coordinator.importManager == nil)
        }

        @Test("isTerminalState is false on fresh coordinator")
        func isTerminalStateIsFalseByDefault() {
            let coordinator = URLImportCoordinator()
            #expect(coordinator.isTerminalState == false)
        }

        @Test("cancelObservation is a no-op on fresh coordinator")
        func cancelObservationOnFreshCoordinator() {
            let coordinator = URLImportCoordinator()
            // Should not crash — there's no task to cancel.
            coordinator.cancelObservation()
            #expect(coordinator.importManager == nil)
        }
    }

    // MARK: - isTerminalState Logic

    @Suite("isTerminalState")
    @MainActor
    struct IsTerminalStateLogic {

        @Test("Returns false when importManager is nil")
        func falseWhenImportManagerNil() {
            let coordinator = URLImportCoordinator()
            #expect(coordinator.importManager == nil)
            #expect(coordinator.isTerminalState == false)
        }
    }

    // MARK: - cancelObservation Safety

    @Suite("cancelObservation")
    @MainActor
    struct CancelObservationSafety {

        @Test("Can be called multiple times without crashing")
        func calledMultipleTimes() {
            let coordinator = URLImportCoordinator()
            coordinator.cancelObservation()
            coordinator.cancelObservation()
            coordinator.cancelObservation()
            // No crash = success
            #expect(coordinator.importManager == nil)
        }

        @Test("importManager remains nil after cancelObservation")
        func importManagerStaysNilAfterCancel() {
            let coordinator = URLImportCoordinator()
            coordinator.cancelObservation()
            #expect(coordinator.importManager == nil)
            #expect(coordinator.isTerminalState == false)
        }
    }
}
