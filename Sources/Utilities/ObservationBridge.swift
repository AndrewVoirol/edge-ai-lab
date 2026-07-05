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

import Observation

// MARK: - Observations AsyncSequence Bridge (WWDC25 / iOS 26+)
//
// These extensions provide typed AsyncSequence access to @Observable
// properties for non-view consumers: automation harness, metrics pipeline,
// AppDelegate callbacks, and testing infrastructure.
//
// Views should NOT use these — they get observation tracking automatically
// via @Environment(ConversationViewModel.self).
//
// Usage:
//   for await isReady in viewModel.engineReadyStream() {
//       print("Engine ready: \(isReady)")
//   }

@MainActor
extension ConversationViewModel {
    /// AsyncSequence that emits whenever `isEngineReady` changes.
    /// Use from non-view async contexts (harness, tests, metrics pipeline).
    func engineReadyStream() -> some AsyncSequence<Bool, Never> {
        Observations { self.isEngineReady }
    }

    /// AsyncSequence that emits whenever `isGenerating` changes.
    func generatingStream() -> some AsyncSequence<Bool, Never> {
        Observations { self.isGenerating }
    }

    /// AsyncSequence that emits whenever `isLoadingModel` changes.
    func modelLoadingStream() -> some AsyncSequence<Bool, Never> {
        Observations { self.isLoadingModel }
    }

    /// AsyncSequence that emits whenever `statusMessage` changes.
    func statusStream() -> some AsyncSequence<String, Never> {
        Observations { self.statusMessage }
    }

    /// AsyncSequence that emits whenever the backend result changes
    /// (e.g., after engine init with GPU → CPU fallback).
    func backendResultStream() -> some AsyncSequence<BackendResult?, Never> {
        Observations { self.backendResult }
    }

    /// AsyncSequence that emits whenever engine config changes are detected
    /// (backend or KV-cache differ from last initialized values).
    func engineConfigChangedStream() -> some AsyncSequence<Bool, Never> {
        Observations { self.engineConfigChanged }
    }
}

// MARK: - Diagnostic Observer

/// Lightweight observer that logs bridge events for automation diagnostics.
/// Attach to a ViewModel to prove the ObservationBridge works end-to-end
/// without changing any harness flow logic.
///
/// Usage:
/// ```swift
/// let observer = DiagnosticObserver(viewModel: vm)
/// observer.start()  // begins logging in background
/// // ... later ...
/// observer.stop()   // cancels the observation task
/// ```
@MainActor
struct DiagnosticObserver {
    private let viewModel: ConversationViewModel
    private var task: Task<Void, Never>?

    init(viewModel: ConversationViewModel) {
        self.viewModel = viewModel
    }

    /// Start observing engine state changes and logging them.
    mutating func start() {
        task = Task { @MainActor [viewModel] in
            for await isReady in viewModel.engineReadyStream() {
                guard !Task.isCancelled else { break }
                automationLog("[DiagnosticObserver] Engine ready: \(isReady)")
            }
        }
    }

    /// Stop the diagnostic observer.
    mutating func stop() {
        task?.cancel()
        task = nil
    }
}
