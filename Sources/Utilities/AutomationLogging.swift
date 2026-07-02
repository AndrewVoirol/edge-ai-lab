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

import os

// MARK: - Automation Logging

/// Shared logger for the automation harness and its pipelines.
///
/// Writes to both stdout (for macOS script parsing) and os_log
/// (for iOS device log capture without --console).
let automationLogger = Logger(subsystem: "com.andrewvoirol.EdgeAILab", category: "automation")

/// Writes a message to both stdout (for macOS script parsing) and os_log
/// (for iOS device log capture without --console).
func automationLog(_ message: String) {
    print(message)
    automationLogger.notice("\(message, privacy: .public)")
}
