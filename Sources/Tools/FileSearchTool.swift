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

// MARK: - FileSearchTool

/// Searches for files by name using Spotlight on macOS or FileManager on iOS.
///
/// Returns metadata (name, path, size, modification date) for matching files.
/// Does **not** read file content — only metadata is returned.
///
/// On macOS, uses `NSMetadataQuery` to search Spotlight with a 5-second timeout.
/// On iOS, recursively searches the app's documents directory.
///
/// Results are capped at 20 to keep response sizes manageable for the model.
struct FileSearchTool: Tool {
    static let name = "search_files"
    static let description = "Search for files by name. Returns file metadata (name, path, size, modified date). Results limited to 20."

    @ToolParam(description: "The filename or keyword to search for, e.g. 'report' or 'notes.txt'")
    var query: String

    func run() async throws -> Any {
        let startTime = CFAbsoluteTimeGetCurrent()
        let argumentsDict: [String: Any] = ["query": query]
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

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            resultString = jsonString(from: [
                "error": "Search query is required"
            ])
            return resultString
        }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let maxResults = 20

        #if os(macOS)
        // Spotlight search via NSMetadataQuery
        let results = await FileSearchTool.spotlightSearch(
            query: trimmedQuery,
            maxResults: maxResults,
            dateFormatter: dateFormatter
        )

        resultString = jsonString(from: [
            "results": results,
            "count": results.count,
            "query": trimmedQuery,
            "source": "spotlight"
        ])
        return resultString

        #elseif os(iOS)
        // FileManager search in app documents
        let results = FileSearchTool.fileManagerSearch(
            query: trimmedQuery,
            maxResults: maxResults,
            dateFormatter: dateFormatter
        )

        resultString = jsonString(from: [
            "results": results,
            "count": results.count,
            "query": trimmedQuery,
            "source": "documents"
        ])
        return resultString
        #endif
    }

    #if os(macOS)
    /// Searches Spotlight using NSMetadataQuery with a 5-second timeout.
    private static func spotlightSearch(
        query: String,
        maxResults: Int,
        dateFormatter: ISO8601DateFormatter
    ) async -> [[String: Any]] {
        await withCheckedContinuation { continuation in
            let metadataQuery = NSMetadataQuery()
            metadataQuery.predicate = NSPredicate(
                format: "kMDItemFSName CONTAINS[cd] %@",
                query
            )
            metadataQuery.searchScopes = [
                NSMetadataQueryUserHomeScope,
                NSMetadataQueryLocalComputerScope
            ]

            var observer: NSObjectProtocol?
            var timeoutTask: DispatchWorkItem?

            // Timeout after 5 seconds
            let timeout = DispatchWorkItem {
                metadataQuery.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                let items = metadataQuery.results as? [NSMetadataItem] ?? []
                let results = FileSearchTool.extractResults(
                    from: items,
                    maxResults: maxResults,
                    dateFormatter: dateFormatter
                )
                continuation.resume(returning: results)
            }
            timeoutTask = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: timeout)

            observer = NotificationCenter.default.addObserver(
                forName: .NSMetadataQueryDidFinishGathering,
                object: metadataQuery,
                queue: .main
            ) { _ in
                timeoutTask?.cancel()
                metadataQuery.stop()
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                let items = metadataQuery.results as? [NSMetadataItem] ?? []
                let results = FileSearchTool.extractResults(
                    from: items,
                    maxResults: maxResults,
                    dateFormatter: dateFormatter
                )
                continuation.resume(returning: results)
            }

            DispatchQueue.main.async {
                metadataQuery.start()
            }
        }
    }

    /// Extracts file metadata from NSMetadataItem results.
    private static func extractResults(
        from items: [NSMetadataItem],
        maxResults: Int,
        dateFormatter: ISO8601DateFormatter
    ) -> [[String: Any]] {
        let limited = items.prefix(maxResults)
        return limited.map { item in
            let name = item.value(forAttribute: kMDItemFSName as String) as? String ?? "unknown"
            let path = item.value(forAttribute: kMDItemPath as String) as? String ?? "unknown"
            let size = item.value(forAttribute: kMDItemFSSize as String) as? Int64 ?? 0
            let modified = item.value(forAttribute: kMDItemFSContentChangeDate as String) as? Date

            var entry: [String: Any] = [
                "name": name,
                "path": path,
                "size": size
            ]
            if let modified {
                entry["modified"] = dateFormatter.string(from: modified)
            } else {
                entry["modified"] = NSNull()
            }
            return entry
        }
    }
    #endif

    #if os(iOS)
    /// Recursively searches the app's documents directory for matching filenames.
    private static func fileManagerSearch(
        query: String,
        maxResults: Int,
        dateFormatter: ISO8601DateFormatter
    ) -> [[String: Any]] {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return []
        }

        var results: [[String: Any]] = []
        let lowercaseQuery = query.lowercased()

        guard let enumerator = fileManager.enumerator(
            at: documentsURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard results.count < maxResults else { break }

            let resourceValues = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
            )
            guard resourceValues?.isRegularFile == true else { continue }

            let filename = fileURL.lastPathComponent
            guard filename.lowercased().contains(lowercaseQuery) else { continue }

            var entry: [String: Any] = [
                "name": filename,
                "path": fileURL.path,
                "size": resourceValues?.fileSize ?? 0
            ]
            if let modified = resourceValues?.contentModificationDate {
                entry["modified"] = dateFormatter.string(from: modified)
            } else {
                entry["modified"] = NSNull()
            }
            results.append(entry)
        }

        return results
    }
    #endif
}
