// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation
import CryptoKit

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

@Suite
struct FileIntegrityCheckerTests {

    // MARK: - Helpers

    /// Creates a temporary directory unique to each test invocation.
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    /// Removes the temporary directory after the test completes.
    private func cleanUp(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Writes `data` to a file named `name` inside `directory` and returns the file URL.
    private func writeFile(
        named name: String,
        in directory: URL,
        contents data: Data
    ) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Tests

    @Test("SHA-256 of known content matches expected hash")
    func testSHA256KnownHash() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let content = "Hello, World!"
        let fileURL = try writeFile(
            named: "known.txt",
            in: tempDir,
            contents: Data(content.utf8)
        )

        let hash = try await FileIntegrityChecker.sha256(of: fileURL)
        let expectedHash = "dffd6021bb2bd5b0af676290809ec3a53191dd81c7f70a4b28688a362182986f"
        #expect(hash == expectedHash)
    }

    @Test("verify returns true when hash matches")
    func testVerifyMatchingHash() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let content = "matching hash test content"
        let fileURL = try writeFile(
            named: "match.txt",
            in: tempDir,
            contents: Data(content.utf8)
        )

        let computedHash = try await FileIntegrityChecker.sha256(of: fileURL)
        let result = try await FileIntegrityChecker.verify(
            file: fileURL,
            expectedHash: computedHash
        )
        #expect(result == true)
    }

    @Test("verify returns false when hash does not match")
    func testVerifyMismatchedHash() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let content = "mismatched hash test content"
        let fileURL = try writeFile(
            named: "mismatch.txt",
            in: tempDir,
            contents: Data(content.utf8)
        )

        let wrongHash = "0000000000000000000000000000000000000000000000000000000000000000"
        let result = try await FileIntegrityChecker.verify(
            file: fileURL,
            expectedHash: wrongHash
        )
        #expect(result == false)
    }

    @Test("sha256 throws fileNotFound for non-existent path")
    func testFileNotFound() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let missingURL = tempDir.appendingPathComponent("does_not_exist.bin")

        do {
            _ = try await FileIntegrityChecker.sha256(of: missingURL)
            Issue.record("Expected IntegrityError.fileNotFound but no error was thrown")
        } catch is FileIntegrityChecker.IntegrityError {
            // Expected — fileNotFound thrown
        }
    }

    @Test("verifyManifest passes when all hashes match")
    func testVerifyManifestAllPass() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let fileA = try writeFile(
            named: "a.txt",
            in: tempDir,
            contents: Data("file a content".utf8)
        )
        let fileB = try writeFile(
            named: "b.txt",
            in: tempDir,
            contents: Data("file b content".utf8)
        )

        let hashA = try await FileIntegrityChecker.sha256(of: fileA)
        let hashB = try await FileIntegrityChecker.sha256(of: fileB)

        let manifest: [(url: URL, expectedHash: String?)] = [
            (fileA, hashA),
            (fileB, hashB),
        ]

        let results = try await FileIntegrityChecker.verifyManifest(files: manifest)

        for result in results {
            #expect(result.verified == true)
        }
    }

    @Test("verifyManifest reports verified=true for nil expectedHash (skipped)")
    func testVerifyManifestWithNilHash() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        let fileA = try writeFile(
            named: "a.txt",
            in: tempDir,
            contents: Data("file a content".utf8)
        )
        let fileB = try writeFile(
            named: "b.txt",
            in: tempDir,
            contents: Data("file b content".utf8)
        )

        let hashA = try await FileIntegrityChecker.sha256(of: fileA)

        let manifest: [(url: URL, expectedHash: String?)] = [
            (fileA, hashA),
            (fileB, nil),
        ]

        let results = try await FileIntegrityChecker.verifyManifest(files: manifest)

        for result in results {
            #expect(result.verified == true)
        }
    }

    @Test("Large file (> 2 MB) streaming hash matches non-streaming CryptoKit hash")
    func testLargeFileStreaming() async throws {
        let tempDir = try makeTempDirectory()
        defer { cleanUp(tempDir) }

        // Create > 2 MB of deterministic data
        let chunkSize = 1024
        let totalChunks = 2100  // ~2.1 MB
        var largeData = Data()
        largeData.reserveCapacity(chunkSize * totalChunks)
        for i in 0..<totalChunks {
            let line = String(repeating: String(i % 10), count: chunkSize)
            largeData.append(Data(line.utf8))
        }

        let fileURL = try writeFile(
            named: "large.bin",
            in: tempDir,
            contents: largeData
        )

        // Compute hash via FileIntegrityChecker (streaming / chunked)
        let streamingHash = try await FileIntegrityChecker.sha256(of: fileURL)

        // Compute hash independently via CryptoKit (non-streaming, entire blob)
        let digest = SHA256.hash(data: largeData)
        let expectedHash = digest.map { String(format: "%02x", $0) }.joined()

        #expect(streamingHash == expectedHash)
    }
}
