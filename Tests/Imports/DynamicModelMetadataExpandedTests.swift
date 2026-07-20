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

@Suite("DynamicModelMetadata — Expanded")
struct DynamicModelMetadataExpandedTests {

    // MARK: - MetadataSource

    @Suite("MetadataSource")
    struct MetadataSourceTests {
        @Test("All raw values are unique strings")
        func rawValues() {
            let sources: [MetadataSource] = [.knownRegistry, .huggingFaceInferred, .kaggle, .userProvided]
            let rawValues = sources.map(\.rawValue)
            #expect(Set(rawValues).count == 4)
        }

        @Test("Codable round-trip preserves values")
        func codableRoundTrip() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            for source in [MetadataSource.knownRegistry, .huggingFaceInferred, .kaggle, .userProvided] {
                let data = try encoder.encode(source)
                let decoded = try decoder.decode(MetadataSource.self, from: data)
                #expect(decoded == source)
            }
        }
    }

    // MARK: - MetadataConfidence

    @Suite("MetadataConfidence")
    struct MetadataConfidenceTests {
        @Test("Comparable ordering: verified > high > medium > low")
        func ordering() {
            #expect(MetadataConfidence.low < MetadataConfidence.medium)
            #expect(MetadataConfidence.medium < MetadataConfidence.high)
            #expect(MetadataConfidence.high < MetadataConfidence.verified)
            #expect(MetadataConfidence.low < MetadataConfidence.verified)
        }

        @Test("sortOrder is consistent with Comparable")
        func sortOrderConsistency() {
            let sorted: [MetadataConfidence] = [.medium, .low, .verified, .high].sorted()
            #expect(sorted == [.low, .medium, .high, .verified])
        }

        @Test("Symbol name is non-empty for all cases")
        func symbolNames() {
            for conf in [MetadataConfidence.verified, .high, .medium, .low] {
                #expect(!conf.symbolName.isEmpty)
            }
        }

        @Test("Label is non-empty for all cases")
        func labels() {
            #expect(MetadataConfidence.verified.label == "Verified Compatible")
            #expect(MetadataConfidence.high.label == "Likely Compatible")
            #expect(MetadataConfidence.medium.label == "Review Recommended")
            #expect(MetadataConfidence.low.label == "Compatibility Unknown")
        }

        @Test("Codable round-trip")
        func codableRoundTrip() throws {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            for conf in [MetadataConfidence.verified, .high, .medium, .low] {
                let data = try encoder.encode(conf)
                let decoded = try decoder.decode(MetadataConfidence.self, from: data)
                #expect(decoded == conf)
            }
        }
    }

    // MARK: - Factory Methods

    @Suite("fromKnownModel")
    struct FromKnownModelTests {
        @Test("Sets source to knownRegistry")
        func source() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromKnownModel(model)
            #expect(entry.source == .knownRegistry)
        }

        @Test("Sets confidence to verified")
        func confidence() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromKnownModel(model)
            #expect(entry.confidence == .verified)
        }

        @Test("Uses modelFile as id")
        func id() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromKnownModel(model)
            #expect(entry.id == model.modelFile)
        }

        @Test("Preserves metadata")
        func metadata() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromKnownModel(model)
            #expect(entry.metadata.displayName == model.displayName)
            #expect(entry.metadata.modelId == model.modelId)
        }
    }

    @Suite("fromHuggingFace")
    struct FromHuggingFaceTests {
        @Test("Sets source to huggingFaceInferred")
        func source() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromHuggingFace(
                repoId: "test/repo",
                metadata: model,
                confidence: .high
            )
            #expect(entry.source == .huggingFaceInferred)
        }

        @Test("Uses repoId as id")
        func id() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromHuggingFace(
                repoId: "test/repo",
                metadata: model,
                confidence: .medium
            )
            #expect(entry.id == "test/repo")
        }

        @Test("Passes through confidence")
        func confidence() {
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromHuggingFace(
                repoId: "test/repo",
                metadata: model,
                confidence: .low
            )
            #expect(entry.confidence == .low)
        }

        @Test("Sets importedAt to recent timestamp")
        func timestamp() {
            let before = Date()
            let model = KnownModelCatalog.allModels[0]
            let entry = DynamicModelMetadata.fromHuggingFace(
                repoId: "test/repo",
                metadata: model,
                confidence: .high
            )
            let after = Date()
            #expect(entry.importedAt >= before)
            #expect(entry.importedAt <= after)
        }
    }

    @Suite("fromKaggle")
    struct FromKaggleTests {
        @Test("Sets source to kaggle")
        func source() {
            let handle = KaggleModelHandle(
                owner: "google",
                modelSlug: "gemma-3n",
                framework: "litert",
                variation: "gemma-3n-e4b-it",
                version: 1
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.source == .kaggle)
        }

        @Test("Sets confidence to low")
        func confidence() {
            let handle = KaggleModelHandle(
                owner: "google",
                modelSlug: "gemma-3n",
                framework: nil,
                variation: nil,
                version: nil
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.confidence == .low)
        }

        @Test("Uses variation as display name when available")
        func variationName() {
            let handle = KaggleModelHandle(
                owner: "google",
                modelSlug: "gemma-3n",
                framework: "litert",
                variation: "gemma-3n-e4b-it",
                version: 1
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.metadata.displayName == "gemma-3n-e4b-it")
        }

        @Test("Falls back to modelSlug when no variation")
        func noVariation() {
            let handle = KaggleModelHandle(
                owner: "google",
                modelSlug: "gemma-3n",
                framework: nil,
                variation: nil,
                version: nil
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.metadata.displayName == "gemma-3n")
        }

        @Test("Constructs modelId from kaggle prefix")
        func modelId() {
            let handle = KaggleModelHandle(
                owner: "google",
                modelSlug: "gemma-3n",
                framework: nil,
                variation: nil,
                version: nil
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.id.contains("kaggle/google/gemma-3n"))
            #expect(entry.metadata.modelId?.contains("kaggle/google/gemma-3n") == true)
        }

        @Test("Sets conservative defaults for unknown metadata")
        func defaults() {
            let handle = KaggleModelHandle(
                owner: "test",
                modelSlug: "model",
                framework: nil,
                variation: nil,
                version: nil
            )
            let entry = DynamicModelMetadata.fromKaggle(
                handle: handle,
                downloadURL: URL(string: "https://kaggle.com/dl")!
            )
            #expect(entry.metadata.fileSizeBytes == 0)
            #expect(entry.metadata.memoryGB == 8)
            #expect(entry.metadata.contextWindowSize == 32_000)
            #expect(entry.metadata.hasVision == false)
            #expect(entry.metadata.hasAudio == false)
            #expect(entry.metadata.runtimeType == .litertlm)
        }
    }
}
