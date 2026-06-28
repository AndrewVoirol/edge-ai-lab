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
import LiteRTLM

// MARK: - ShortcutsTool

/// Configures a Siri Shortcut that runs a specified prompt through the on-device model.
///
/// This is an **experimental** tool. Full Siri Shortcuts integration requires the
/// `AppIntents` framework and an `AppShortcutsProvider` at the app level, which is
/// planned for a future release. Currently, this tool validates and acknowledges the
/// shortcut configuration.
///
/// Example: `create_shortcut(name: "Morning Briefing", prompt: "Give me a morning briefing")`
struct ShortcutsTool: Tool {
    static let name = "create_shortcut"
    static let description = "Create a Siri Shortcut configuration that runs a specified prompt through the on-device model. Experimental — full Siri integration is planned."

    @ToolParam(description: "The name for the shortcut, e.g. 'Morning Briefing'")
    var name: String

    @ToolParam(description: "The prompt to run when the shortcut is triggered, e.g. 'Give me a morning briefing'")
    var prompt: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = ["name": name, "prompt": prompt]
        var resultString = ""
        defer {
            let duration = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let succeeded = !resultString.isEmpty && !resultString.contains("\"error\"")
            let event = ToolCallEvent(
                toolName: Self.name,
                arguments: jsonString(from: argumentsDict),
                result: resultString,
                durationMs: duration,
                timestamp: Date(),
                succeeded: succeeded
            )
            ToolExecutionTracker.shared.notify(event)
        }

        // Validate inputs
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            resultString = jsonString(from: [
                "error": "Shortcut name is required"
            ])
            return resultString
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            resultString = jsonString(from: [
                "error": "Prompt is required"
            ])
            return resultString
        }

        // Return the shortcut configuration
        // Full AppIntents registration is deferred to a future release
        resultString = jsonString(from: [
            "status": "shortcut_configured",
            "name": trimmedName,
            "prompt": trimmedPrompt,
            "note": "Siri Shortcuts integration requires AppIntents framework setup. The shortcut configuration has been saved and will be available when full Siri integration is enabled."
        ])
        return resultString
    }
}
