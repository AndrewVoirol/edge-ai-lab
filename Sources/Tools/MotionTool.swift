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
#if os(iOS)
import CoreMotion
#endif

// MARK: - MotionTool

/// Returns a single sample of accelerometer, gyroscope, and attitude data from the
/// device's motion sensors.
///
/// This tool is iOS-only. On macOS it returns an error because Macs do not have
/// the IMU hardware that `CMMotionManager` requires.
struct MotionTool: Tool {
    static let name = "get_device_motion"
    static let description = "Get accelerometer, gyroscope, and attitude data from the device's motion sensors. iOS only — not available on macOS."

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

        #if os(iOS)
        let motionManager = CMMotionManager()

        guard motionManager.isDeviceMotionAvailable else {
            resultString = jsonString(from: [
                "error": "Motion sensors are not available on this device"
            ])
            return resultString
        }

        motionManager.deviceMotionUpdateInterval = 0.1

        let deviceMotion: CMDeviceMotion = await withCheckedContinuation { continuation in
            motionManager.startDeviceMotionUpdates(
                using: .xMagneticNorthZVertical,
                to: .main
            ) { motion, _ in
                guard let motion else { return }
                motionManager.stopDeviceMotionUpdates()
                continuation.resume(returning: motion)
            }
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())

        resultString = jsonString(from: [
            "accelerometer": [
                "x": String(format: "%.4f", deviceMotion.userAcceleration.x),
                "y": String(format: "%.4f", deviceMotion.userAcceleration.y),
                "z": String(format: "%.4f", deviceMotion.userAcceleration.z)
            ],
            "gyroscope": [
                "x": String(format: "%.4f", deviceMotion.rotationRate.x),
                "y": String(format: "%.4f", deviceMotion.rotationRate.y),
                "z": String(format: "%.4f", deviceMotion.rotationRate.z)
            ],
            "attitude": [
                "roll": String(format: "%.4f", deviceMotion.attitude.roll),
                "pitch": String(format: "%.4f", deviceMotion.attitude.pitch),
                "yaw": String(format: "%.4f", deviceMotion.attitude.yaw)
            ],
            "magnetic_heading": String(format: "%.4f", deviceMotion.heading),
            "timestamp": timestamp
        ])
        return resultString

        #elseif os(macOS)
        resultString = jsonString(from: [
            "error": "Motion sensors are not available on macOS"
        ])
        return resultString
        #endif
    }
}
