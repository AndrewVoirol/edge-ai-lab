// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

/// Shared date formatting utilities. Extracted from view-specific helpers
/// to eliminate duplication and enable unit testing.
///
/// Following the project's `enum`-namespace pattern (see `ModelDetailFormatters`,
/// `EvalRunnerLogic`) to prevent accidental instantiation.
enum DateFormatters {
    /// Formats a date as a compact relative timestamp (e.g. "Just now", "5m ago",
    /// "Yesterday", "Jul 15").
    ///
    /// Used in sidebar conversation rows, iOS picker sheets, and anywhere
    /// a human-friendly timestamp is needed without full date precision.
    static func relativeTimestamp(_ date: Date, relativeTo now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 172800 { return "Yesterday" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
