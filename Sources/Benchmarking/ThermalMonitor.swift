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

// MARK: - Thermal Monitor

/// Observes system thermal state change notifications and records transitions.
///
/// Usage:
/// 1. Call `startMonitoring()` before inference begins.
/// 2. Call `stopMonitoring()` after inference completes.
/// 3. Read `transitions` to get all thermal state changes that occurred.
///
/// Thread safety: The notification observer fires on the posting thread (typically main).
/// Access to `transitions` is synchronized via a lock for safe cross-thread reads.
final class ThermalMonitor: @unchecked Sendable {

    /// Lock for thread-safe access to mutable state.
    private let lock = NSLock()

    /// Accumulated thermal transitions during the current monitoring session.
    private var _transitions: [ThermalTransition] = []

    /// The thermal level when monitoring started, used to detect the first transition.
    private var _lastKnownLevel: ThermalLevel?

    /// The notification observer token for removal on stop.
    private var observer: NSObjectProtocol?

    /// Whether monitoring is currently active.
    private var _isMonitoring = false

    /// Thread-safe read of the accumulated transitions.
    var transitions: [ThermalTransition] {
        lock.lock()
        defer { lock.unlock() }
        return _transitions
    }

    /// Whether the monitor is currently active.
    var isMonitoring: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isMonitoring
    }

    /// Start observing thermal state changes.
    /// Records the current thermal level as the baseline.
    /// Calling this while already monitoring restarts the session (clears previous transitions).
    func startMonitoring() {
        lock.lock()
        _transitions.removeAll()
        _lastKnownLevel = ThermalLevel(from: ProcessInfo.processInfo.thermalState)
        _isMonitoring = true
        lock.unlock()

        // Remove any existing observer before adding a new one
        if let existing = observer {
            NotificationCenter.default.removeObserver(existing)
        }

        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.handleThermalStateChange()
        }
    }

    /// Stop observing thermal state changes and finalize the transitions list.
    func stopMonitoring() {
        if let existing = observer {
            NotificationCenter.default.removeObserver(existing)
            observer = nil
        }

        lock.lock()
        _isMonitoring = false
        lock.unlock()
    }

    /// Handle a thermal state change notification.
    private func handleThermalStateChange() {
        let newLevel = ThermalLevel(from: ProcessInfo.processInfo.thermalState)

        lock.lock()
        guard _isMonitoring else {
            lock.unlock()
            return
        }

        let previousLevel = _lastKnownLevel ?? .nominal
        if newLevel != previousLevel {
            let transition = ThermalTransition(
                from: previousLevel,
                to: newLevel,
                timestamp: Date()
            )
            _transitions.append(transition)
            _lastKnownLevel = newLevel
        }
        lock.unlock()
    }

    deinit {
        if let existing = observer {
            NotificationCenter.default.removeObserver(existing)
        }
    }
}
