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

import CoreLocation
import Foundation
import LiteRTLM
import MapKit

// MARK: - LocationDelegate

/// Bridges `CLLocationManagerDelegate` callbacks into a single async result
/// via `withCheckedThrowingContinuation`.
private final class LocationDelegate: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<CLLocation, Error>?

    func setContinuation(_ continuation: CheckedContinuation<CLLocation, Error>) {
        self.continuation = continuation
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        continuation?.resume(returning: location)
        continuation = nil
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

// MARK: - LocationTool

/// Returns GPS coordinates and a reverse-geocoded address for the current device location.
///
/// On iOS, coordinates come from GPS/cellular triangulation. On macOS, location is
/// determined via Wi-Fi triangulation and is typically less precise.
struct LocationTool: Tool {
    static let name = "get_location"
    static let description = "Get the device's current GPS coordinates and reverse-geocoded address including street, city, state, country, and postal code"

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

        // Check that location services are enabled at the system level
        guard CLLocationManager.locationServicesEnabled() else {
            resultString = jsonString(from: [
                "error": "Location services are not available. Please enable location access in Settings."
            ])
            return resultString
        }

        let manager = CLLocationManager()
        let delegate = LocationDelegate()
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyBest

        // Check authorization status
        let status: CLAuthorizationStatus
        #if os(iOS)
        status = manager.authorizationStatus
        #elseif os(macOS)
        status = manager.authorizationStatus
        #endif

        switch status {
        case .denied, .restricted:
            resultString = jsonString(from: [
                "error": "Location services are not available. Please enable location access in Settings."
            ])
            return resultString
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            break
        }

        // Request a single location update via continuation
        let location: CLLocation
        do {
            location = try await withCheckedThrowingContinuation { continuation in
                delegate.setContinuation(continuation)
                manager.requestLocation()
            }
        } catch {
            resultString = jsonString(from: [
                "error": "Location services are not available. Please enable location access in Settings."
            ])
            return resultString
        }

        // Reverse-geocode to get a human-readable address
        var addressDict: [String: Any] = [
            "street": NSNull(),
            "city": NSNull(),
            "state": NSNull(),
            "country": NSNull(),
            "postal_code": NSNull()
        ]

        if #available(macOS 26.0, iOS 26.0, *) {
            if let request = MKReverseGeocodingRequest(location: location) {
                if let mapItems = try? await request.mapItems,
                   let item = mapItems.first {
                    let placemark = item.placemark
                    addressDict["street"] = placemark.thoroughfare as Any? ?? NSNull()
                    addressDict["city"] = placemark.locality as Any? ?? NSNull()
                    addressDict["state"] = placemark.administrativeArea as Any? ?? NSNull()
                    addressDict["country"] = placemark.country as Any? ?? NSNull()
                    addressDict["postal_code"] = placemark.postalCode as Any? ?? NSNull()
                }
            }
        } else {
            if let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location),
               let placemark = placemarks.first {
                addressDict["street"] = placemark.thoroughfare as Any? ?? NSNull()
                addressDict["city"] = placemark.locality as Any? ?? NSNull()
                addressDict["state"] = placemark.administrativeArea as Any? ?? NSNull()
                addressDict["country"] = placemark.country as Any? ?? NSNull()
                addressDict["postal_code"] = placemark.postalCode as Any? ?? NSNull()
            }
        }

        let source: String
        #if os(iOS)
        source = "gps"
        #elseif os(macOS)
        source = "wifi"
        #endif

        resultString = jsonString(from: [
            "latitude": String(format: "%.6f", location.coordinate.latitude),
            "longitude": String(format: "%.6f", location.coordinate.longitude),
            "altitude": String(format: "%.2f", location.altitude),
            "horizontal_accuracy": String(format: "%.2f", location.horizontalAccuracy),
            "address": addressDict,
            "source": source
        ])
        return resultString
    }
}
