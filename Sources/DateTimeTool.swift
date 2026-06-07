import Foundation
import LiteRTLM

// MARK: - DateTimeTool

/// Returns the current date, time, and timezone information.
///
/// Optionally accepts an IANA timezone identifier to report the time in a
/// different timezone. Defaults to the device's current timezone.
///
/// Example prompts:
/// - `get_current_datetime()` → current local time
/// - `get_current_datetime(timezone: "Asia/Tokyo")` → current time in Tokyo
struct DateTimeTool: Tool {
    static let name = "get_current_datetime"
    static let description = "Get the current date, time, and timezone information"

    @ToolParam(description: "IANA timezone identifier, e.g. 'America/New_York'. Defaults to device timezone.")
    var timezone: String = ""

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict = ["timezone": timezone]
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
        let now = Date()
        let tz: TimeZone
        if !timezone.isEmpty, let requested = TimeZone(identifier: timezone) {
            tz = requested
        } else if !timezone.isEmpty {
            resultString = jsonString(from: [
                "error": "Unknown timezone identifier: '\(timezone)'",
                "available_example": "America/New_York, Europe/London, Asia/Tokyo"
            ])
            return resultString
        } else {
            tz = TimeZone.current
        }


        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = tz
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "HH:mm:ss"
        let timeString = dateFormatter.string(from: now)

        dateFormatter.dateFormat = "EEEE"
        let dayOfWeek = dateFormatter.string(from: now)

        let offsetSeconds = tz.secondsFromGMT(for: now)
                let sign = offsetSeconds < 0 ? "-" : "+"
        let absSeconds = abs(offsetSeconds)
        let offsetHours = absSeconds / 3600
        let offsetMinutes = (absSeconds % 3600) / 60
        let utcOffset = String(format: "%@%02d:%02d", sign, offsetHours, offsetMinutes)

        resultString = jsonString(from: [
            "date": dateString,
            "time": timeString,
            "timezone": tz.identifier,
            "utc_offset": utcOffset,
            "unix_timestamp": now.timeIntervalSince1970,
            "day_of_week": dayOfWeek,
            "is_dst": tz.isDaylightSavingTime(for: now)
        ])
        return resultString
    }
}
