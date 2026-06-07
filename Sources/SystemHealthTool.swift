import Foundation
import LiteRTLM
#if os(iOS)
import UIKit
#endif

// MARK: - SystemHealthTool

/// Introspects the model's own runtime environment — thermal state, memory pressure,
/// battery level, and disk space.
///
/// This is the **killer differentiator** for on-device function calling: the model
/// can reason about its own hardware constraints. For example:
/// - "Am I running hot? Should I keep my responses shorter?"
/// - "How much memory is available for my context window?"
/// - "Is the device plugged in or running on battery?"
///
/// Uses `DeviceMetrics` for thermal and memory data, `UIDevice` for battery info
/// on iOS, and `FileManager` for disk space.
struct SystemHealthTool: Tool {
    static let name = "get_system_health"
    static let description = "Get the system health status including thermal state, memory, battery, and disk space. Useful for understanding the device's current operational constraints."

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
        let thermalLevel = DeviceMetrics.currentThermalLevel
        let availableMemoryMB = DeviceMetrics.availableMemoryMB
        let totalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        // Thermal state with emoji indicator
        let thermalEmoji: String
        switch thermalLevel {
        case .nominal:  thermalEmoji = "🟢"
        case .fair:     thermalEmoji = "🟡"
        case .serious:  thermalEmoji = "🟠"
        case .critical: thermalEmoji = "🔴"
        }

        var result: [String: Any] = [
            "thermal_state": thermalLevel.label,
            "thermal_indicator": thermalEmoji,
            "thermal_symbol": thermalLevel.symbolName,
            "available_memory_mb": String(format: "%.0f", availableMemoryMB),
            "total_memory_gb": String(format: "%.1f", totalMemoryGB),
            "memory_pressure": availableMemoryMB < 500 ? "high" :
                               availableMemoryMB < 1500 ? "moderate" : "low",
            "processor_count": ProcessInfo.processInfo.processorCount,
            "active_processor_count": ProcessInfo.processInfo.activeProcessorCount
        ]

        // Battery info — iOS only via UIDevice
        #if os(iOS)
        await MainActor.run {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let batteryLevel = await MainActor.run { UIDevice.current.batteryLevel }
        let batteryState = await MainActor.run { UIDevice.current.batteryState }

        if batteryLevel >= 0 {
            result["battery_level_percent"] = Int(batteryLevel * 100)
        } else {
            result["battery_level_percent"] = "unavailable"
        }

        let batteryStateString: String
        switch batteryState {
        case .unknown:    batteryStateString = "unknown"
        case .unplugged:  batteryStateString = "unplugged"
        case .charging:   batteryStateString = "charging"
        case .full:       batteryStateString = "full"
        @unknown default: batteryStateString = "unknown"
        }
        result["battery_state"] = batteryStateString
        #else
        result["battery_level_percent"] = "not_available_on_macos"
        result["battery_state"] = "not_available_on_macos"
        #endif

        // Disk space available
        if let attributes = try? FileManager.default.attributesOfFileSystem(
            forPath: NSHomeDirectory()
        ),
           let freeSpace = attributes[.systemFreeSize] as? Int64 {
            let freeSpaceGB = Double(freeSpace) / 1_073_741_824.0
            result["disk_space_available_gb"] = String(format: "%.1f", freeSpaceGB)
        } else {
            result["disk_space_available_gb"] = "unavailable"
        }

        // System uptime
        let uptime = ProcessInfo.processInfo.systemUptime
        let uptimeHours = Int(uptime / 3600)
        let uptimeMinutes = Int((uptime.truncatingRemainder(dividingBy: 3600)) / 60)
        result["system_uptime"] = "\(uptimeHours)h \(uptimeMinutes)m"

        resultString = jsonString(from: result)
        return resultString
    }
}
