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
import Observation

// MARK: - HuggingFace API Response Models

/// Metadata for a single model returned by the HuggingFace API.
///
/// Maps to the JSON response from `GET /api/models/{id}` and `GET /api/models?author=...`.
/// Uses `CodingKeys` to bridge between the API's snake_case field names and Swift conventions.
///
/// Example API response fields:
/// ```json
/// {
///   "id": "litert-community/gemma-4-E2B-it-litert-lm",
///   "author": "litert-community",
///   "lastModified": "2026-06-01T12:00:00.000Z",
///   "downloads": 12345,
///   "likes": 42,
///   "tags": ["gemma-4", "litert", "text-generation"],
///   "pipeline_tag": "text-generation",
///   "library_name": "litert",
///   "siblings": [...]
/// }
/// ```
struct HFModelInfo: Codable, Sendable, Identifiable {

    /// The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    let id: String

    /// The organization or user that owns the repository.
    /// May be absent from the list endpoint — falls back to parsing from `id`.
    let author: String

    /// ISO-8601 timestamp of the last modification.
    /// May be absent from the list endpoint.
    let lastModified: String

    /// Total download count reported by HuggingFace.
    let downloads: Int

    /// Number of likes on the model page.
    let likes: Int

    /// Tags attached to the model (e.g., "gemma-4", "litert", "text-generation").
    let tags: [String]

    /// The pipeline tag (e.g., "text-generation", "image-classification").
    let pipelineTag: String?

    /// The library name (e.g., "litert", "transformers", "mlx").
    let libraryName: String?

    /// File listing for the repository. Only populated on detail endpoint responses.
    let siblings: [HFSibling]?

    enum CodingKeys: String, CodingKey {
        case id, author, lastModified, downloads, likes, tags, siblings
        case pipelineTag = "pipeline_tag"
        case libraryName = "library_name"
        case createdAt
    }

    /// Custom decoder to handle missing fields from the HF list endpoint.
    /// The list endpoint omits `author`, `lastModified`, and sometimes other fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        // author may be missing from list endpoint — parse from id ("org/repo" → "org")
        author = (try? container.decode(String.self, forKey: .author))
            ?? String(id.split(separator: "/").first ?? Substring(id))
        // lastModified may be missing — fall back to createdAt or empty
        lastModified = (try? container.decode(String.self, forKey: .lastModified))
            ?? (try? container.decode(String.self, forKey: .createdAt))
            ?? ""
        downloads = (try? container.decode(Int.self, forKey: .downloads)) ?? 0
        likes = (try? container.decode(Int.self, forKey: .likes)) ?? 0
        tags = (try? container.decode([String].self, forKey: .tags)) ?? []
        pipelineTag = try? container.decode(String.self, forKey: .pipelineTag)
        libraryName = try? container.decode(String.self, forKey: .libraryName)
        siblings = try? container.decode([HFSibling].self, forKey: .siblings)
    }

    /// Custom encoder — only encodes stored properties (skips `createdAt` decode-only key).
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(author, forKey: .author)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(downloads, forKey: .downloads)
        try container.encode(likes, forKey: .likes)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(pipelineTag, forKey: .pipelineTag)
        try container.encodeIfPresent(libraryName, forKey: .libraryName)
        try container.encodeIfPresent(siblings, forKey: .siblings)
    }

    /// Memberwise init for tests and previews.
    init(id: String, author: String, lastModified: String = "",
         downloads: Int = 0, likes: Int = 0, tags: [String] = [],
         pipelineTag: String? = nil, libraryName: String? = nil,
         siblings: [HFSibling]? = nil) {
        self.id = id
        self.author = author
        self.lastModified = lastModified
        self.downloads = downloads
        self.likes = likes
        self.tags = tags
        self.pipelineTag = pipelineTag
        self.libraryName = libraryName
        self.siblings = siblings
    }
}


// MARK: - HFSibling

/// A single file entry within a HuggingFace repository.
///
/// Returned as part of the `siblings` array on `HFModelInfo`.
/// The `lfs` field is present when the file is stored via Git LFS (large files).
struct HFSibling: Codable, Sendable {

    /// Relative filename within the repository (e.g., "gemma-4-E2B-it.litertlm").
    let rfilename: String

    /// File size in bytes. May be nil for non-LFS files in list responses.
    let size: Int64?

    /// Git LFS metadata, present only for LFS-tracked files.
    let lfs: HFLFSInfo?
}

// MARK: - HFLFSInfo

/// Git LFS metadata for a file in a HuggingFace repository.
///
/// When a file is tracked by Git LFS, the actual content is stored externally.
/// The `size` here is the real file size, while `pointerSize` is the size of the
/// LFS pointer file in the Git repository.
struct HFLFSInfo: Codable, Sendable {

    /// The LFS object ID (SHA-256 hash of the file content).
    let oid: String

    /// Actual file size in bytes (the real content, not the pointer).
    let size: Int64

    /// Size of the LFS pointer file in bytes.
    let pointerSize: Int

    enum CodingKeys: String, CodingKey {
        case oid, size
        case pointerSize = "pointer_size"
    }
}

// MARK: - Model Format Detection

/// Detected model format based on file contents of a HuggingFace repository.
///
/// Used to determine which runtime engine a discovered model requires:
/// - `.litertlm`: Google's LiteRT-LM format — runs via the LiteRT engine.
/// - `.mlx`: Apple MLX format — requires the MLX Swift runtime.
/// - `.unknown`: Format could not be determined from the file listing.
enum HFModelFormat: String, Sendable {
    /// LiteRT-LM packaged model (single `.litertlm` archive).
    case litertlm
    /// MLX model directory (contains `config.json` + `*.safetensors` weight shards).
    case mlx
    /// Format could not be determined from the repository file listing.
    case unknown
}

// MARK: - HFModelBrowser Errors

/// Errors specific to HuggingFace API operations.
enum HFModelBrowserError: LocalizedError {
    case invalidURL(String)
    case httpError(statusCode: Int, repoId: String)
    case decodingFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid HuggingFace API URL: \(url)"
        case .httpError(let statusCode, let repoId):
            return "HuggingFace API returned HTTP \(statusCode) for \(repoId)."
        case .decodingFailed(let underlying):
            return "Failed to decode HuggingFace API response: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - HFModelBrowser

/// Client for the HuggingFace Models API, used to discover and inspect models.
///
/// **Usage:**
/// ```swift
/// let browser = HFModelBrowser()
/// await browser.refreshGemmaModels()
/// for model in browser.discoveredModels {
///     print("\(model.displayName) — \(browser.detectFormat(model))")
/// }
/// ```
///
/// **Authentication:** If a HuggingFace token is stored via `HFTokenStorage`,
/// all API requests include a Bearer token header. This is required for gated
/// models (e.g., `google/*` repos) but optional for public repos like
/// `litert-community`.
///
/// **Caching:** List results are cached in-memory by organization name to avoid
/// redundant API calls during a session. The cache is cleared when the browser
/// is deallocated.
@Observable
final class HFModelBrowser {

    // MARK: - Constants

    /// Base URL for the HuggingFace models API.
    private static let apiBaseURL = "https://huggingface.co/api/models"

    /// Base URL for file downloads (resolve endpoint).
    private static let resolveBaseURL = "https://huggingface.co"

    // MARK: - Published State

    /// Models discovered by the most recent `refreshGemmaModels()` call.
    /// Updated on the MainActor.
    var discoveredModels: [HFModelInfo] = []

    /// Whether a fetch operation is currently in progress.
    var isLoading: Bool = false

    /// Human-readable description of the last error, or nil if the last operation succeeded.
    var lastError: String?

    // MARK: - Private State

    /// In-memory cache of list results, keyed by organization/author name.
    private var cache: [String: [HFModelInfo]] = [:]

    /// Shared JSON decoder configured for HuggingFace API responses.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // Note: We use explicit CodingKeys for snake_case fields (pipeline_tag, library_name,
        // pointer_size) rather than .convertFromSnakeCase, because lastModified arrives as
        // camelCase from the API and would be broken by the blanket conversion strategy.
        return decoder
    }()

    // MARK: - List Models

    /// Fetch a list of models from a specific HuggingFace author/organization.
    ///
    /// Results are sorted by download count (descending) and cached in-memory
    /// by author name for the lifetime of this browser instance.
    ///
    /// - Parameters:
    ///   - author: The HuggingFace username or organization (e.g., "litert-community").
    ///   - search: Optional search query to filter model names.
    ///   - limit: Maximum number of results to return (default: 20).
    /// - Returns: An array of `HFModelInfo` matching the query.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func listModels(author: String, search: String? = nil, limit: Int = 20) async throws -> [HFModelInfo] {
        // Build cache key incorporating search to avoid stale results
        let cacheKey = search != nil ? "\(author):\(search!)" : author
        if let cached = cache[cacheKey] {
            return cached
        }

        // Build URL with query parameters
        var components = URLComponents(string: Self.apiBaseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        if let search = search {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw HFModelBrowserError.invalidURL(components.string ?? "nil")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available (required for gated repos)
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw HFModelBrowserError.httpError(statusCode: httpResponse.statusCode, repoId: author)
        }

        do {
            let models = try decoder.decode([HFModelInfo].self, from: data)
            cache[cacheKey] = models
            return models
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Model Detail

    /// Fetch full details for a specific model, including the file listing with sizes.
    ///
    /// Unlike `listModels`, the detail endpoint always returns the `siblings` array
    /// with LFS metadata, enabling file size inspection and format detection.
    ///
    /// - Parameter repoId: The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    /// - Returns: The full `HFModelInfo` with populated `siblings`.
    /// - Throws: `HFModelBrowserError` on network or decoding failures.
    func modelDetail(repoId: String) async throws -> HFModelInfo {
        let urlString = "\(Self.apiBaseURL)/\(repoId)"
        guard let url = URL(string: urlString) else {
            throw HFModelBrowserError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        // Attach HF token if available
        if let token = HFTokenStorage.retrieve() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw HFModelBrowserError.httpError(statusCode: httpResponse.statusCode, repoId: repoId)
        }

        do {
            return try decoder.decode(HFModelInfo.self, from: data)
        } catch {
            throw HFModelBrowserError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Refresh Gemma Models

    /// Discover Gemma 4 models from known community organizations.
    ///
    /// Fetches from both `litert-community` (LiteRT-LM format) and `mlx-community`
    /// (MLX format), searching for "gemma-4" variants. Results are merged, deduplicated
    /// by repo ID, and stored in `discoveredModels`.
    ///
    /// This method updates `isLoading` and `lastError` on the MainActor for UI binding.
    func refreshGemmaModels() async {
        await MainActor.run {
            isLoading = true
            lastError = nil
        }

        do {
            async let litertModels = listModels(author: "litert-community", search: "gemma-4")
            async let mlxModels = listModels(author: "mlx-community", search: "gemma-4")

            let litert = try await litertModels
            let mlx = try await mlxModels

            // Merge results, litert-community first (primary format for this app)
            var merged: [HFModelInfo] = []
            var seenIds: Set<String> = []
            for model in litert + mlx {
                if seenIds.insert(model.id).inserted {
                    merged.append(model)
                }
            }

            let finalModels = merged
            await MainActor.run {
                discoveredModels = finalModels
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                isLoading = false
            }
        }
    }

    /// Detect the model format from file listing, metadata, or naming conventions.
    ///
    /// Priority:
    /// 1. If `siblings` is populated, inspect filenames (.litertlm, .safetensors)
    /// 2. Otherwise, infer from `libraryName` and `tags` metadata
    /// 3. Fall back to model ID pattern matching
    func detectFormat(_ model: HFModelInfo) -> HFModelFormat {
        // 1. Check siblings if available (detail endpoint)
        if let siblings = model.siblings {
            let filenames = siblings.map(\.rfilename)

            if filenames.contains(where: { $0.hasSuffix(".litertlm") }) {
                return .litertlm
            }

            let hasConfig = filenames.contains("config.json")
            let hasSafetensors = filenames.contains(where: { $0.hasSuffix(".safetensors") })
            if hasConfig && hasSafetensors {
                return .mlx
            }
        }

        // 2. Infer from library_name metadata (returned by list endpoint)
        if let lib = model.libraryName?.lowercased() {
            if lib.contains("litert") {
                return .litertlm
            }
            if lib == "mlx" {
                return .mlx
            }
        }

        // 3. Infer from tags
        if model.tags.contains(where: { $0.lowercased().contains("litert") }) {
            return .litertlm
        }
        if model.tags.contains(where: { $0.lowercased() == "mlx" }) {
            return .mlx
        }

        // 4. Infer from model ID naming convention
        if model.id.lowercased().contains("litert-lm") || model.id.lowercased().contains("litert_lm") {
            return .litertlm
        }
        if model.author.lowercased() == "mlx-community" {
            return .mlx
        }

        return .unknown
    }

    // MARK: - Model Size

    /// Extract the size of the largest model file from the repository's file listing.
    ///
    /// Prefers LFS sizes (actual content size) over regular file sizes. This gives
    /// the best estimate for download size of the primary model artifact.
    ///
    /// - Parameter model: The model info with populated `siblings`.
    /// - Returns: The size in bytes of the largest file, or nil if no file sizes are available.
    func modelSize(_ model: HFModelInfo) -> Int64? {
        guard let siblings = model.siblings else {
            return nil
        }

        let sizes: [Int64] = siblings.compactMap { sibling in
            // Prefer LFS size (actual content size) over the regular size field
            if let lfs = sibling.lfs {
                return lfs.size
            }
            return sibling.size
        }

        return sizes.max()
    }

    // MARK: - Download URL Construction

    /// Construct a direct download URL for a file in a HuggingFace repository.
    ///
    /// Uses the `/resolve/{revision}/{filename}` endpoint which serves the raw file
    /// content, following LFS redirects automatically.
    ///
    /// - Parameters:
    ///   - repoId: The full repository ID (e.g., "litert-community/gemma-4-E2B-it-litert-lm").
    ///   - filename: The file to download (e.g., "gemma-4-E2B-it.litertlm").
    ///   - revision: The Git revision to download from (default: "main").
    /// - Returns: The fully qualified download URL.
    static func downloadURL(repoId: String, filename: String, revision: String = "main") -> URL {
        // Force-unwrap is safe here: all components are URL-safe strings from the HF API
        URL(string: "\(resolveBaseURL)/\(repoId)/resolve/\(revision)/\(filename)")!
    }

    // MARK: - Cache Management

    /// Clear the in-memory model cache, forcing fresh API requests on next fetch.
    func clearCache() {
        cache.removeAll()
    }
}

// MARK: - HFModelInfo Convenience Extensions

extension HFModelInfo {

    /// Human-readable model name extracted from the full repository ID.
    ///
    /// Strips the organization prefix and returns just the model name portion.
    /// For example, `"litert-community/gemma-4-E2B-it-litert-lm"` → `"gemma-4-E2B-it-litert-lm"`.
    var displayName: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[id.index(after: slashIndex)...])
        }
        return id
    }

    /// Organization or user name extracted from the full repository ID.
    ///
    /// For example, `"litert-community/gemma-4-E2B-it-litert-lm"` → `"litert-community"`.
    var orgName: String {
        if let slashIndex = id.firstIndex(of: "/") {
            return String(id[..<slashIndex])
        }
        return id
    }

    /// Whether this model is a Gemma 4 variant, detected from tags or the repository ID.
    var isGemma4: Bool {
        tags.contains(where: { $0.lowercased().contains("gemma-4") || $0.lowercased().contains("gemma4") })
            || id.lowercased().contains("gemma-4")
            || id.lowercased().contains("gemma4")
    }

    /// Quantization information extracted from the model name or tags.
    ///
    /// Looks for common quantization indicators such as "4bit", "8bit", "bf16", "fp16",
    /// "int4", "int8", "q4", "q8", etc. Returns nil if no quantization info is detected.
    ///
    /// Examples:
    /// - `"mlx-community/gemma-4-4bit"` → `"4bit"`
    /// - `"mlx-community/gemma-4-E2B-it-bf16"` → `"bf16"`
    var quantizationInfo: String? {
        // Known quantization patterns to search for, ordered by specificity
        let patterns = [
            "bf16", "fp16", "fp32",
            "int4", "int8",
            "4bit", "8bit",
            "q4_0", "q4_1", "q4_k_m", "q4_k_s",
            "q5_0", "q5_1", "q5_k_m", "q5_k_s",
            "q6_k",
            "q8_0",
        ]

        let lowerId = id.lowercased()

        // Check the repo ID first (most reliable source)
        for pattern in patterns {
            if lowerId.contains(pattern) {
                return pattern
            }
        }

        // Fall back to tags
        for tag in tags {
            let lowerTag = tag.lowercased()
            for pattern in patterns {
                if lowerTag.contains(pattern) {
                    return pattern
                }
            }
        }

        return nil
    }
}
