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
import Network
#if os(macOS)
import CoreWLAN
#endif

// MARK: - WiFiTool

/// Returns network connectivity information for the device.
///
/// Uses `NWPathMonitor` on both platforms for connection status and interface type.
/// On macOS, supplements with `CoreWLAN` data (SSID, signal strength).
/// On iOS, reports interface type and connection status.
///
/// Does **not** perform speed tests — only reports connectivity metadata.
struct WiFiTool: Tool {
    static let name = "get_network_info"
    static let description = "Get network connectivity information including connection status, interface type (wifi/cellular/ethernet), and Wi-Fi details on macOS."

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

        // Get network path status via NWPathMonitor
        let pathInfo = await WiFiTool.getNetworkPath()

        var result: [String: Any] = [
            "status": pathInfo.status,
            "interface_type": pathInfo.interfaceType,
            "is_expensive": pathInfo.isExpensive,
            "is_constrained": pathInfo.isConstrained
        ]

        #if os(macOS)
        // macOS: Add CoreWLAN Wi-Fi details
        if let wifiClient = CWWiFiClient.shared().interface() {
            result["wifi_ssid"] = wifiClient.ssid() ?? NSNull()
            result["wifi_rssi"] = wifiClient.rssiValue()
            result["wifi_noise"] = wifiClient.noiseMeasurement()
            result["wifi_channel"] = wifiClient.wlanChannel()?.channelNumber ?? NSNull()
        } else {
            result["wifi_ssid"] = NSNull()
            result["wifi_rssi"] = NSNull()
        }
        result["platform"] = "macOS"
        #elseif os(iOS)
        result["platform"] = "iOS"
        // iOS: Network interface type is already reported via NWPathMonitor
        // CTTelephonyNetworkInfo is deprecated on iOS 16+ and provides limited info
        result["note"] = "Wi-Fi SSID requires NEHotspotHelper entitlement on iOS"
        #endif

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        result["timestamp"] = formatter.string(from: Date())

        resultString = jsonString(from: result)
        return resultString
    }

    // MARK: - Network Path Info

    /// Captures a single network path update via NWPathMonitor.
    private static func getNetworkPath() async -> NetworkPathInfo {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "com.edgeailab.networkmonitor")

            monitor.pathUpdateHandler = { path in
                monitor.cancel()

                let status: String
                switch path.status {
                case .satisfied:
                    status = "connected"
                case .unsatisfied:
                    status = "disconnected"
                case .requiresConnection:
                    status = "requires_connection"
                @unknown default:
                    status = "unknown"
                }

                let interfaceType: String
                if path.usesInterfaceType(.wifi) {
                    interfaceType = "wifi"
                } else if path.usesInterfaceType(.cellular) {
                    interfaceType = "cellular"
                } else if path.usesInterfaceType(.wiredEthernet) {
                    interfaceType = "ethernet"
                } else if path.usesInterfaceType(.loopback) {
                    interfaceType = "loopback"
                } else {
                    interfaceType = "other"
                }

                continuation.resume(returning: NetworkPathInfo(
                    status: status,
                    interfaceType: interfaceType,
                    isExpensive: path.isExpensive,
                    isConstrained: path.isConstrained
                ))
            }

            monitor.start(queue: queue)
        }
    }
}

// MARK: - NetworkPathInfo

/// Lightweight struct to carry NWPath data out of the callback closure.
private struct NetworkPathInfo {
    let status: String
    let interfaceType: String
    let isExpensive: Bool
    let isConstrained: Bool
}
