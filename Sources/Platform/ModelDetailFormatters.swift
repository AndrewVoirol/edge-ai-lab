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

/// Pure formatting helpers for model detail display.
/// Extracted from `iOSModelDetailView` for cross-platform reuse and testability.
enum ModelDetailFormatters {

    /// Format a byte count for display (e.g. "4.2 GB").
    static func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Format a context window size for display (e.g. "8K ctx", "1M ctx").
    static func formattedContextWindow(_ size: Int) -> String {
        if size >= 1_000_000 {
            return "\(size / 1_000_000)M ctx"
        } else if size >= 1_000 {
            return "\(size / 1_000)K ctx"
        } else {
            return "\(size) ctx"
        }
    }
}
