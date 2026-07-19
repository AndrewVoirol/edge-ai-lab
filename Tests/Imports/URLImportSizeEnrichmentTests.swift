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

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - URLImportSizeEnrichment Tests

/// Tests for the Step 7 size-enrichment logic in `URLImportManager`.
///
/// The production code enriches `HFSibling` file sizes by cross-referencing
/// the tree API's `HFTreeEntry` data. This suite extracts that logic into a
/// standalone pure function and validates all edge cases.
@Suite("URLImportSizeEnrichment")
struct URLImportSizeEnrichmentTests {

    // MARK: - Extracted enrichment logic (mirrors Step 7)

    /// Replicates the size-enrichment logic from `URLImportManager.resolveMetadata`.
    ///
    /// For each sibling that lacks size data, looks up the file size from
    /// tree entries, preferring `lfs.size` over `entry.size`.
    private static func enrichFileSizes(
        siblings: [HFSibling],
        treeEntries: [HFTreeEntry]
    ) -> [HFSibling] {
        let sizeLookup = Dictionary(
            treeEntries.compactMap { entry -> (String, Int64)? in
                // Prefer LFS size (actual file size) over entry size (pointer size)
                guard let size = entry.lfs?.size ?? entry.size else { return nil }
                return (entry.path, size)
            },
            uniquingKeysWith: { first, _ in first }
        )
        return siblings.map { sibling in
            if sibling.size != nil || sibling.lfs != nil {
                return sibling // Already has size data
            }
            guard let treeSize = sizeLookup[sibling.rfilename] else { return sibling }
            // Create a new HFSibling with the size from tree API
            return HFSibling(rfilename: sibling.rfilename, size: treeSize, lfs: sibling.lfs)
        }
    }

    // MARK: - Tests

    @Test("Siblings with no size get enriched from tree LFS size")
    func siblingsEnrichedFromTreeLFS() {
        let siblings = [
            HFSibling(rfilename: "model.safetensors", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 135, // pointer size
                path: "model.safetensors",
                lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 4_200_000_000, pointerSize: 135)
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].rfilename == "model.safetensors")
        #expect(result[0].size == 4_200_000_000)
        #expect(result[0].lfs == nil) // lfs from sibling is nil, not copied from tree
    }

    @Test("Siblings that already have size are not overwritten")
    func existingSizePreserved() {
        let siblings = [
            HFSibling(rfilename: "model.safetensors", size: 999, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 135,
                path: "model.safetensors",
                lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 4_200_000_000, pointerSize: 135)
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].size == 999, "Existing size should not be overwritten")
    }

    @Test("Siblings that already have LFS info are not overwritten")
    func existingLFSPreserved() {
        let originalLFS = HFLFSInfo(oid: "sha256:original", size: 777, pointerSize: nil)
        let siblings = [
            HFSibling(rfilename: "model.safetensors", size: nil, lfs: originalLFS)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 135,
                path: "model.safetensors",
                lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 4_200_000_000, pointerSize: 135)
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].lfs?.size == 777, "Existing LFS info should not be overwritten")
        #expect(result[0].size == nil, "Size should remain nil when LFS is present")
    }

    @Test("Tree entries with no matching sibling are safely ignored")
    func unmatchedTreeEntriesIgnored() {
        let siblings = [
            HFSibling(rfilename: "config.json", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 4_200_000_000,
                path: "model.safetensors",
                lfs: nil
            ),
            HFTreeEntry(
                type: "file",
                oid: "def456",
                size: 2_100_000_000,
                path: "model-part2.safetensors",
                lfs: nil
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].rfilename == "config.json")
        #expect(result[0].size == nil, "No matching tree entry, so size should remain nil")
    }

    @Test("Empty tree entries leave siblings unchanged")
    func emptyTreeEntriesNoChange() {
        let siblings = [
            HFSibling(rfilename: "model.safetensors", size: nil, lfs: nil),
            HFSibling(rfilename: "config.json", size: nil, lfs: nil)
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: [])

        #expect(result.count == 2)
        #expect(result[0].size == nil)
        #expect(result[1].size == nil)
    }

    @Test("Mixed siblings: only those missing size are enriched")
    func mixedSiblingsPartialEnrichment() {
        let siblings = [
            HFSibling(rfilename: "model.safetensors", size: nil, lfs: nil),
            HFSibling(rfilename: "tokenizer.json", size: 500_000, lfs: nil),
            HFSibling(rfilename: "config.json", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc",
                size: nil,
                path: "model.safetensors",
                lfs: HFTreeLFSInfo(oid: "sha256:abc", size: 4_200_000_000, pointerSize: 135)
            ),
            HFTreeEntry(
                type: "file",
                oid: "def",
                size: 500_000,
                path: "tokenizer.json",
                lfs: nil
            ),
            HFTreeEntry(
                type: "file",
                oid: "ghi",
                size: 1_024,
                path: "config.json",
                lfs: nil
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 3)
        // model.safetensors: had no size → enriched from LFS
        #expect(result[0].size == 4_200_000_000)
        // tokenizer.json: already had size → preserved
        #expect(result[1].size == 500_000)
        // config.json: had no size → enriched from entry.size
        #expect(result[2].size == 1_024)
    }

    @Test("Tree entry with size but no LFS uses entry.size")
    func treeEntryWithSizeNoLFS() {
        let siblings = [
            HFSibling(rfilename: "config.json", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 2_048,
                path: "config.json",
                lfs: nil
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].size == 2_048, "Should use entry.size when lfs is nil")
    }

    @Test("Tree entry with both size and LFS prefers LFS size")
    func treeEntryPrefersLFSOverEntrySize() {
        let siblings = [
            HFSibling(rfilename: "model.bin", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc123",
                size: 135, // pointer size (small)
                path: "model.bin",
                lfs: HFTreeLFSInfo(oid: "sha256:abc123", size: 8_000_000_000, pointerSize: 135)
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result[0].size == 8_000_000_000, "LFS size should take priority over entry size")
    }

    @Test("Empty siblings returns empty result")
    func emptySiblingsReturnsEmpty() {
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: "abc",
                size: 1_000,
                path: "model.safetensors",
                lfs: nil
            )
        ]

        let result = Self.enrichFileSizes(siblings: [], treeEntries: treeEntries)

        #expect(result.isEmpty)
    }

    @Test("Tree entry with nil size and nil LFS is skipped in lookup")
    func treeEntryWithNoSizeDataSkipped() {
        let siblings = [
            HFSibling(rfilename: "readme.md", size: nil, lfs: nil)
        ]
        let treeEntries = [
            HFTreeEntry(
                type: "file",
                oid: nil,
                size: nil,
                path: "readme.md",
                lfs: nil
            )
        ]

        let result = Self.enrichFileSizes(siblings: siblings, treeEntries: treeEntries)

        #expect(result.count == 1)
        #expect(result[0].size == nil, "No size data in tree entry, so sibling stays unchanged")
    }
}
