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
import os

// MARK: - Kaggle Model Handle

/// Parsed components from a Kaggle model URL.
///
/// Kaggle model URLs come in two forms:
/// - **Basic:** `https://www.kaggle.com/models/{owner}/{model_slug}`
/// - **Full:** `https://www.kaggle.com/models/{owner}/{model_slug}/{framework}/{variation}/{version}`
///
/// The basic form identifies the model but lacks the specificity needed to construct
/// a download URL. The full form includes framework, variation, and version, which
/// are required by the Kaggle download API.
struct KaggleModelHandle: Sendable {

    /// The model owner/organization (e.g., "google").
    let owner: String

    /// The model slug (e.g., "gemma-3n").
    let modelSlug: String

    /// The framework identifier (e.g., "litert", "pyTorch"). Nil for basic URLs.
    let framework: String?

    /// The variation identifier (e.g., "gemma-3n-e4b-it", "2b"). Nil for basic URLs.
    let variation: String?

    /// The version number (e.g., 1). Nil for basic URLs.
    let version: Int?
}

// MARK: - Kaggle Model Parser

/// Parses Kaggle model URLs and constructs API requests for model downloads.
///
/// **Supported URL Formats:**
/// - `https://www.kaggle.com/models/{owner}/{model_slug}`
/// - `https://www.kaggle.com/models/{owner}/{model_slug}/{framework}/{variation}/{version}`
/// - `https://kaggle.com/models/...` (without www)
///
/// **Download API:**
/// - Endpoint: `GET https://www.kaggle.com/api/v1/models/{owner}/{model}/{framework}/{variation}/{version}/download`
/// - Auth: HTTP Basic Auth with `username:apiKey` (from kaggle.json)
/// - Response: `.tar.gz` archive containing model files
///
/// **Usage:**
/// ```swift
/// if let handle = KaggleModelParser.parseURL(urlString) {
///     if let downloadURL = KaggleModelParser.buildDownloadURL(handle: handle) {
///         let authHeader = KaggleModelParser.buildAuthHeader(username: user, apiKey: key)
///         // ... start download
///     }
/// }
/// ```
enum KaggleModelParser {

    private static let logger = Logger(
        subsystem: "com.andrewvoirol.GemmaEdgeGallery",
        category: "kaggleModelParser"
    )

    // MARK: - URL Parsing

    /// Parse a Kaggle model URL into its components.
    ///
    /// Handles both basic and full URL formats, with or without `www.` prefix
    /// and trailing slashes.
    ///
    /// - Parameter urlString: The URL string to parse.
    /// - Returns: A `KaggleModelHandle` with parsed components, or nil if the URL is invalid.
    static func parseURL(_ urlString: String) -> KaggleModelHandle? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host?.lowercased() else {
            return nil
        }

        // Validate host — accept kaggle.com and www.kaggle.com
        guard host == "kaggle.com" || host == "www.kaggle.com" else {
            return nil
        }

        // Extract path components, filtering empty strings (handles trailing slash)
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        // Must start with "models" segment
        guard pathComponents.count >= 3,
              pathComponents[0].lowercased() == "models" else {
            return nil
        }

        let owner = pathComponents[1]
        let modelSlug = pathComponents[2]

        // Full URL: /models/{owner}/{slug}/{framework}/{variation}/{version}
        if pathComponents.count >= 6,
           let version = Int(pathComponents[5]) {
            let handle = KaggleModelHandle(
                owner: owner,
                modelSlug: modelSlug,
                framework: pathComponents[3],
                variation: pathComponents[4],
                version: version
            )
            logger.info(
                "🔗 Parsed full Kaggle URL: \(owner, privacy: .public)/\(modelSlug, privacy: .public)/\(pathComponents[3], privacy: .public)/\(pathComponents[4], privacy: .public)/\(version)"
            )
            return handle
        }

        // Basic URL: /models/{owner}/{slug}
        let handle = KaggleModelHandle(
            owner: owner,
            modelSlug: modelSlug,
            framework: nil,
            variation: nil,
            version: nil
        )
        logger.info(
            "🔗 Parsed basic Kaggle URL: \(owner, privacy: .public)/\(modelSlug, privacy: .public)"
        )
        return handle
    }

    // MARK: - Download URL Construction

    /// Build the Kaggle API download URL from a parsed handle.
    ///
    /// The download API requires all five components (owner, model, framework,
    /// variation, version). Returns nil if any of the framework/variation/version
    /// fields are missing (i.e., for basic URLs).
    ///
    /// - Parameter handle: The parsed Kaggle model handle.
    /// - Returns: The download API URL, or nil if the handle lacks required components.
    static func buildDownloadURL(handle: KaggleModelHandle) -> URL? {
        guard let framework = handle.framework,
              let variation = handle.variation,
              let version = handle.version else {
            logger.warning(
                "⚠️ Cannot build download URL: missing framework/variation/version for \(handle.owner, privacy: .public)/\(handle.modelSlug, privacy: .public)"
            )
            return nil
        }

        let urlString = "https://www.kaggle.com/api/v1/models/\(handle.owner)/\(handle.modelSlug)/\(framework)/\(variation)/\(version)/download"

        guard let url = URL(string: urlString) else {
            logger.error("❌ Failed to construct download URL: \(urlString, privacy: .public)")
            return nil
        }

        logger.info("📦 Built Kaggle download URL: \(urlString, privacy: .public)")
        return url
    }

    // MARK: - Authentication

    /// Build an HTTP Basic Auth header value from Kaggle credentials.
    ///
    /// Kaggle API uses HTTP Basic Authentication with the format:
    /// `Basic base64(username:apiKey)`
    ///
    /// Credentials are typically stored in `~/.kaggle/kaggle.json`:
    /// ```json
    /// {"username": "your_username", "key": "your_api_key"}
    /// ```
    ///
    /// - Parameters:
    ///   - username: The Kaggle username.
    ///   - apiKey: The Kaggle API key.
    /// - Returns: The `Authorization` header value string.
    static func buildAuthHeader(username: String, apiKey: String) -> String {
        let credentials = "\(username):\(apiKey)"
        let encoded = Data(credentials.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
