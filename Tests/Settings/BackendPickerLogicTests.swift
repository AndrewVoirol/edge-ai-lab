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

/// Tests for `BackendPickerLogic` — pure-function logic for the GPU/CPU backend picker.
/// Written TDD-first: these tests define the expected behavior before implementation.
@Suite("BackendPickerLogic")
struct BackendPickerLogicTests {

    // MARK: - Available Backends

    @Suite("Available Backends Filtering")
    struct AvailableBackends {

        @Test("GPU-only model shows only GPU option")
        func gpuOnlyModel_onlyShowsGPU() {
            let options = BackendPickerLogic.availableBackends(for: .gpuOnly)
            #expect(options == [.gpu])
        }

        @Test("CPU-only model shows only CPU option")
        func cpuOnlyModel_onlyShowsCPU() {
            let options = BackendPickerLogic.availableBackends(for: .cpuOnly)
            #expect(options == [.cpu])
        }

        @Test("GPU+CPU model shows both options")
        func gpuAndCpuModel_showsBothOptions() {
            let options = BackendPickerLogic.availableBackends(for: .gpuAndCpu)
            #expect(options.contains(.gpu))
            #expect(options.contains(.cpu))
            #expect(options.count == 2)
        }

        @Test("Unknown capability shows both options with GPU first")
        func unknownCapability_showsBothWithGPUFirst() {
            let options = BackendPickerLogic.availableBackends(for: .unknown)
            #expect(options.contains(.gpu))
            #expect(options.contains(.cpu))
            #expect(options.first == .gpu)
        }
    }

    // MARK: - Default Backend

    @Suite("Default Backend Selection")
    struct DefaultBackend {

        @Test("Default backend prefers GPU for GPU+CPU models")
        func defaultBackend_prefersGPU() {
            let backend = BackendPickerLogic.defaultBackend(for: .gpuAndCpu)
            #expect(backend == .gpu)
        }

        @Test("Default backend is CPU for CPU-only models")
        func defaultBackend_cpuOnlyModel_selectsCPU() {
            let backend = BackendPickerLogic.defaultBackend(for: .cpuOnly)
            #expect(backend == .cpu)
        }

        @Test("Default backend is GPU for GPU-only models")
        func defaultBackend_gpuOnlyModel_selectsGPU() {
            let backend = BackendPickerLogic.defaultBackend(for: .gpuOnly)
            #expect(backend == .gpu)
        }

        @Test("Default backend prefers GPU for unknown capability")
        func defaultBackend_unknown_prefersGPU() {
            let backend = BackendPickerLogic.defaultBackend(for: .unknown)
            #expect(backend == .gpu)
        }
    }

    // MARK: - Restart Detection

    @Suite("Restart Detection")
    struct RestartDetection {

        @Test("Changing backend requires restart")
        func changingBackend_requiresRestart() {
            let result = BackendPickerLogic.requiresRestart(current: .gpu, proposed: .cpu)
            #expect(result == true)
        }

        @Test("Same backend does not require restart")
        func sameBackend_doesNotRequireRestart() {
            let result = BackendPickerLogic.requiresRestart(current: .gpu, proposed: .gpu)
            #expect(result == false)
        }

        @Test("Changing CPU to GPU requires restart")
        func cpuToGpu_requiresRestart() {
            let result = BackendPickerLogic.requiresRestart(current: .cpu, proposed: .gpu)
            #expect(result == true)
        }
    }

    // MARK: - Picker Enabled State

    @Suite("Picker Enabled State")
    struct PickerEnabled {

        @Test("Picker disabled when no model loaded")
        func noModelLoaded_pickerDisabled() {
            let enabled = BackendPickerLogic.isPickerEnabled(modelLoaded: false)
            #expect(enabled == false)
        }

        @Test("Picker enabled when model loaded")
        func modelLoaded_pickerEnabled() {
            let enabled = BackendPickerLogic.isPickerEnabled(modelLoaded: true)
            #expect(enabled == true)
        }
    }

    // MARK: - BackendOption Properties

    @Suite("BackendOption Properties")
    struct BackendOptionProperties {

        @Test("GPU option has correct display name")
        func gpuDisplayName() {
            #expect(BackendOption.gpu.displayName == "GPU")
        }

        @Test("CPU option has correct display name")
        func cpuDisplayName() {
            #expect(BackendOption.cpu.displayName == "CPU")
        }

        @Test("GPU option has correct icon")
        func gpuIcon() {
            #expect(BackendOption.gpu.iconName == "gpu")
        }

        @Test("CPU option has correct icon")
        func cpuIcon() {
            #expect(BackendOption.cpu.iconName == "cpu")
        }

        @Test("All BackendOption cases are iterable")
        func allCasesIterable() {
            #expect(BackendOption.allCases.count >= 2)
            #expect(BackendOption.allCases.contains(.gpu))
            #expect(BackendOption.allCases.contains(.cpu))
        }

        @Test("BackendOption is identifiable by rawValue")
        func identifiable() {
            let gpu = BackendOption.gpu
            let cpu = BackendOption.cpu
            #expect(gpu.id != cpu.id)
        }
    }

    // MARK: - Maps to useGPU Bool

    @Suite("Backend to useGPU Mapping")
    struct BackendToUseGPU {

        @Test("GPU maps to useGPU=true")
        func gpuMapsToTrue() {
            #expect(BackendPickerLogic.useGPU(for: .gpu) == true)
        }

        @Test("CPU maps to useGPU=false")
        func cpuMapsToFalse() {
            #expect(BackendPickerLogic.useGPU(for: .cpu) == false)
        }
    }
}
