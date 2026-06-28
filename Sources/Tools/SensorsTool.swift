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
import CoreLocation
import UIKit
#endif

// MARK: - SensorsTool

/// Returns environmental sensor data from the device: barometric pressure,
/// compass heading, and proximity state.
///
/// This tool is iOS-only. On macOS it returns a graceful degradation error
/// because Macs do not have barometers, magnetometers, or proximity sensors.
///
/// Combines three sensor types into a single tool call:
/// - **CMAltimeter**: Barometric pressure (kPa) and relative altitude (m)
/// - **CLLocationManager heading**: Magnetic and true heading (degrees)
/// - **UIDevice proximity**: Whether something is near the proximity sensor
struct SensorsTool: Tool {
    static let name = "get_sensors"
    static let description = "Get environmental sensor data including barometric pressure, compass heading, and proximity state. iOS only — not available on macOS."

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
        var result: [String: Any] = [:]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        result["timestamp"] = formatter.string(from: Date())

        // Barometric pressure via CMAltimeter
        if CMAltimeter.isRelativeAltitudeAvailable() {
            let altimeter = CMAltimeter()
            let altimeterData: CMAltitudeData? = await withCheckedContinuation { continuation in
                altimeter.startRelativeAltitudeUpdates(to: .main) { data, _ in
                    altimeter.stopRelativeAltitudeUpdates()
                    continuation.resume(returning: data)
                }
            }

            if let data = altimeterData {
                result["barometric_pressure"] = [
                    "pressure_kpa": String(format: "%.3f", data.pressure.doubleValue),
                    "relative_altitude_m": String(format: "%.2f", data.relativeAltitude.doubleValue),
                    "available": true
                ]
            } else {
                result["barometric_pressure"] = [
                    "available": false,
                    "reason": "Failed to read altimeter data"
                ]
            }
        } else {
            result["barometric_pressure"] = [
                "available": false,
                "reason": "Altimeter not available on this device"
            ]
        }

        // Compass heading via CLLocationManager
        let headingResult = await SensorsTool.readHeading()
        result["compass"] = headingResult

        // Proximity sensor via UIDevice
        let proximityEnabled = await MainActor.run {
            UIDevice.current.isProximityMonitoringEnabled = true
            return UIDevice.current.isProximityMonitoringEnabled
        }
        if proximityEnabled {
            let proximityState = await MainActor.run {
                UIDevice.current.proximityState
            }
            result["proximity"] = [
                "is_close": proximityState,
                "available": true
            ]
            // Disable monitoring after reading
            await MainActor.run {
                UIDevice.current.isProximityMonitoringEnabled = false
            }
        } else {
            result["proximity"] = [
                "available": false,
                "reason": "Proximity monitoring not supported on this device"
            ]
        }

        result["platform"] = "iOS"
        resultString = jsonString(from: result)
        return resultString

        #elseif os(macOS)
        resultString = jsonString(from: [
            "error": "Sensors not available on macOS",
            "platform": "macOS"
        ])
        return resultString
        #endif
    }

    #if os(iOS)
    /// Reads a single compass heading using CLLocationManager with async/await.
    private static func readHeading() async -> [String: Any] {
        guard CLLocationManager.headingAvailable() else {
            return [
                "available": false,
                "reason": "Heading not available on this device"
            ]
        }

        let manager = CLLocationManager()
        let delegate = HeadingDelegate()
        manager.delegate = delegate

        let heading: CLHeading? = await withCheckedContinuation { continuation in
            delegate.setContinuation(continuation)
            manager.startUpdatingHeading()
        }
        manager.stopUpdatingHeading()

        if let heading {
            return [
                "magnetic_heading": String(format: "%.1f", heading.magneticHeading),
                "true_heading": String(format: "%.1f", heading.trueHeading),
                "heading_accuracy": String(format: "%.1f", heading.headingAccuracy),
                "available": true
            ]
        } else {
            return [
                "available": false,
                "reason": "Failed to read heading data"
            ]
        }
    }
    #endif
}

// MARK: - HeadingDelegate

#if os(iOS)
/// Bridges `CLLocationManagerDelegate` heading callbacks into a single async result.
private final class HeadingDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<CLHeading?, Never>?

    func setContinuation(_ continuation: CheckedContinuation<CLHeading?, Never>) {
        self.continuation = continuation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        continuation?.resume(returning: newHeading)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
#endif
