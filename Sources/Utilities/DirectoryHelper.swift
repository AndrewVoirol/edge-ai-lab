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

// MARK: - Directory Helper

/// Centralized, safe access to standard app directories.
///
/// Eliminates scattered `FileManager.default.urls(for:in:).first!` force-unwraps
/// by providing a single, documented unwrap point. On Apple platforms,
/// `FileManager.urls(for:in:)` with `.userDomainMask` always returns at least
/// one URL, so this is technically safe — but centralizing the unwrap makes the
/// codebase more defensive and easier to audit.
enum DirectoryHelper {

    /// The app's `Application Support` directory.
    ///
    /// Path: `~/Library/Application Support/` (macOS) or app container (iOS).
    /// Creates the directory if it doesn't exist.
    static var applicationSupport: URL {
        // swiftlint:disable:next force_unwrap
        // Safe: .userDomainMask always returns ≥1 result on Apple platforms.
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first! // Centralized unwrap — see class doc

        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The app's `Documents` directory.
    ///
    /// Path: `~/Documents/` (macOS) or app container Documents (iOS).
    static var documents: URL {
        // swiftlint:disable:next force_unwrap
        // Safe: .userDomainMask always returns ≥1 result on Apple platforms.
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first! // Centralized unwrap — see class doc
    }
}
