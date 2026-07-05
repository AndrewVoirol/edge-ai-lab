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

// MARK: - BackendOption

/// Represents a selectable inference backend.
/// Extensible for future NPU support.
enum BackendOption: String, CaseIterable, Identifiable, Sendable, Equatable {
    case gpu
    case cpu

    var id: String { rawValue }

    /// Human-readable display name for UI labels.
    var displayName: String {
        switch self {
        case .gpu: return "GPU"
        case .cpu: return "CPU"
        }
    }

    /// SF Symbol name for the backend icon.
    var iconName: String {
        switch self {
        case .gpu: return "gpu"
        case .cpu: return "cpu"
        }
    }
}

// MARK: - BackendPickerLogic

/// Pure-function logic for the GPU/CPU backend picker.
/// Extracted from view code for testability per project conventions.
/// Views call these static methods; no instance state.
enum BackendPickerLogic {

    /// Returns the list of available backend options for the given platform capability.
    ///
    /// - Parameter capability: The model's `BackendCapability` on the current platform.
    /// - Returns: Filtered and ordered list of `BackendOption` values.
    static func availableBackends(for capability: BackendCapability) -> [BackendOption] {
        switch capability {
        case .gpuOnly:
            return [.gpu]
        case .cpuOnly:
            return [.cpu]
        case .gpuAndCpu, .unknown:
            // GPU first — preferred default ordering
            return [.gpu, .cpu]
        }
    }

    /// Returns the recommended default backend for the given capability.
    /// Prefers GPU when available.
    ///
    /// - Parameter capability: The model's `BackendCapability` on the current platform.
    /// - Returns: The default `BackendOption` to pre-select.
    static func defaultBackend(for capability: BackendCapability) -> BackendOption {
        switch capability {
        case .cpuOnly:
            return .cpu
        case .gpuOnly, .gpuAndCpu, .unknown:
            return .gpu
        }
    }

    /// Whether changing from the current to the proposed backend requires engine re-initialization.
    ///
    /// - Parameters:
    ///   - current: The currently active backend.
    ///   - proposed: The newly selected backend.
    /// - Returns: `true` if the engine must be restarted.
    static func requiresRestart(current: BackendOption, proposed: BackendOption) -> Bool {
        current != proposed
    }

    /// Whether the backend picker should be enabled.
    /// Disabled when no model is loaded (no capability info available).
    ///
    /// - Parameter modelLoaded: Whether a model is currently loaded.
    /// - Returns: `true` if the picker should be interactive.
    static func isPickerEnabled(modelLoaded: Bool) -> Bool {
        modelLoaded
    }

    /// Maps a `BackendOption` to the `useGPU` boolean used by `ModelSessionController`.
    /// Bridges the new typed API to the existing engine initialization parameter.
    ///
    /// - Parameter option: The selected backend option.
    /// - Returns: `true` for GPU, `false` for CPU.
    static func useGPU(for option: BackendOption) -> Bool {
        option == .gpu
    }
}
