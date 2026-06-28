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

// MARK: - CameraTool

/// Signals that the user wants to attach a photo to the conversation.
///
/// Because `Tool.run()` executes outside the UI layer, this tool cannot directly
/// present a photo picker. Instead it posts a `Notification.Name.showPhotoPickerRequested`
/// notification (defined in `DesignSystem.swift`) that the view layer observes and
/// responds to by presenting the system photo picker or camera interface.
struct CameraTool: Tool {
    static let name = "take_photo"
    static let description = "Trigger the photo picker so the user can select or take a photo to attach to the conversation"

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = [:]
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

        // Post notification for the UI layer to present the photo picker
        await MainActor.run {
            NotificationCenter.default.post(name: .showPhotoPickerRequested, object: nil)
        }

        resultString = jsonString(from: [
            "status": "photo_picker_requested",
            "message": "The photo picker has been triggered. The user can now select a photo to attach to the conversation."
        ])
        return resultString
    }
}
