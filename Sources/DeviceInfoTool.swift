import Foundation
import LiteRTLM
#if os(iOS)
import UIKit
#endif

// MARK: - DeviceInfoTool

/// Returns hardware and software information about the device running the model.
///
/// Uses the project's `DeviceMetrics` utility for consistent thermal and memory
/// reporting. This tool lets the model understand its execution environment.
struct DeviceInfoTool: Tool {
    static let name = "get_device_info"
    static let description = "Get device hardware and software information including model, OS version, processor, memory, and thermal state"

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
        let availableMemory = DeviceMetrics.formattedAvailableMemory

        let platform: String
        let osVersion: String
        #if os(iOS)
        platform = "iOS"
        osVersion = await UIDevice.current.systemVersion
        #elseif os(macOS)
        platform = "macOS"
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #else
        platform = "unknown"
        osVersion = "unknown"
        #endif

        let processorCount = ProcessInfo.processInfo.processorCount
        let activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0

        resultString = jsonString(from: [
            "device_model": DeviceMetrics.deviceModel,
            "platform": platform,
            "os_version": osVersion,
            "processor_count": processorCount,
            "active_processor_count": activeProcessorCount,
            "physical_memory_gb": String(format: "%.1f", physicalMemoryGB),
            "available_memory": availableMemory,
            "thermal_state": thermalLevel.label,
            "thermal_symbol": thermalLevel.symbolName
        ])
        return resultString
    }
}
