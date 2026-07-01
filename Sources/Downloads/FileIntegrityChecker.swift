// Copyright 2026 Andrew Voirol. Apache-2.0

import CryptoKit
import Foundation

/// Memory-efficient SHA-256 hash verification for downloaded model files.
/// Uses streaming/chunked reads to handle multi-GB safetensors files
/// without loading them entirely into memory.
enum FileIntegrityChecker {

    // MARK: - Error Types

    enum IntegrityError: LocalizedError {
        case fileNotFound(String)
        case readError(String)
        case hashMismatch(expected: String, actual: String, filename: String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .readError(let detail):
                return "Failed to read file: \(detail)"
            case .hashMismatch(let expected, let actual, let filename):
                return "Hash mismatch for \(filename): expected \(expected), got \(actual)"
            }
        }
    }

    // MARK: - Constants

    /// 1 MB chunk size for streaming reads.
    private static let chunkSize = 1_048_576

    // MARK: - Public API

    /// Compute SHA-256 hash of a file using streaming reads.
    /// Uses 1 MB chunks to avoid loading entire files into memory.
    /// - Parameter fileURL: URL of the file to hash.
    /// - Returns: Lowercase hex-encoded SHA-256 digest string.
    /// - Throws: `IntegrityError.fileNotFound` if the file doesn't exist,
    ///           `IntegrityError.readError` if the file can't be read.
    static func sha256(of fileURL: URL) async throws -> String {
        let path = fileURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw IntegrityError.fileNotFound(path)
        }

        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw IntegrityError.readError("Unable to open file handle for \(path)")
        }
        defer { try? handle.close() }

        var hasher = SHA256()

        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: chunkSize)
            } catch {
                throw IntegrityError.readError(
                    "Error reading chunk from \(fileURL.lastPathComponent): \(error.localizedDescription)"
                )
            }

            guard let data = chunk, !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Verify a downloaded file matches the expected SHA-256 hash.
    /// Returns true if the hash matches, false otherwise.
    /// - Parameters:
    ///   - file: URL of the file to verify.
    ///   - expectedHash: The expected lowercase hex-encoded SHA-256 hash.
    /// - Returns: `true` if the computed hash matches `expectedHash` (case-insensitive).
    /// - Throws: `IntegrityError` if the file can't be read or hashed.
    static func verify(file: URL, expectedHash: String) async throws -> Bool {
        let actual = try await sha256(of: file)
        return actual.lowercased() == expectedHash.lowercased()
    }

    /// Verify all files in a directory download manifest.
    /// Returns array of (filename, passed) results.
    ///
    /// Files with a `nil` expected hash are marked as verified (skip check).
    /// - Parameter files: Array of tuples containing file URLs and optional expected hashes.
    /// - Returns: Array of `(filename, verified)` results for each entry.
    /// - Throws: `IntegrityError` if any file can't be read or hashed.
    static func verifyManifest(
        files: [(url: URL, expectedHash: String?)]
    ) async throws -> [(filename: String, verified: Bool)] {
        var results: [(filename: String, verified: Bool)] = []

        for entry in files {
            let filename = entry.url.lastPathComponent

            guard let expected = entry.expectedHash else {
                // No hash provided — treat as verified (nothing to check).
                results.append((filename: filename, verified: true))
                continue
            }

            let passed = try await verify(file: entry.url, expectedHash: expected)
            results.append((filename: filename, verified: passed))
        }

        return results
    }
}
