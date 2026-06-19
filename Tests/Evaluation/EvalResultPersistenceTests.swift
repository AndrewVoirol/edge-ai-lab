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

// MARK: - Helpers

/// Shared test factory methods for creating eval domain objects.
/// The Export types only have `init(from:)` taking domain objects, so we build
/// those domain objects here and let the Export inits do the mapping.
private enum TestFactory {

    static func makePromptResult(
        promptText: String = "What is 2+2?",
        response: String = "The answer is 4.",
        passed: Bool = true,
        score: EvalScore = .pass,
        decodeSpeed: Double? = 42.0,
        ttft: Double? = 0.85,
        toolCallEvents: [ToolCallEvent] = [],
        duration: TimeInterval = 3.5
    ) -> PromptEvalResult {
        PromptEvalResult(
            promptId: UUID(),
            promptText: promptText,
            response: response,
            passed: passed,
            score: score,
            decodeSpeed: decodeSpeed,
            ttft: ttft,
            toolCallEvents: toolCallEvents,
            duration: duration
        )
    }

    static func makeModelResult(
        modelName: String = "Gemma 3n E2B",
        modelFile: String = "gemma-3n-E2B-it.litertlm",
        promptResults: [PromptEvalResult]? = nil,
        toolCallAccuracy: Double? = nil,
        peakMemoryDeltaMB: Double? = 128.5,
        thermalTransitions: Int = 1
    ) -> ModelEvalResult {
        let prompts = promptResults ?? [
            makePromptResult(passed: true),
            makePromptResult(
                promptText: "What is the capital of France?",
                response: "Paris is the capital of France.",
                passed: true,
                score: .pass,
                decodeSpeed: 38.0,
                ttft: 0.92,
                duration: 4.0
            ),
        ]
        return ModelEvalResult(
            modelName: modelName,
            modelFile: modelFile,
            avgDecodeSpeed: 40.0,
            avgTTFT: 0.88,
            p95Latency: 25.5,
            totalTokensGenerated: 500,
            totalDuration: 30.0,
            promptResults: prompts,
            toolCallAccuracy: toolCallAccuracy,
            peakMemoryDeltaMB: peakMemoryDeltaMB,
            thermalTransitions: thermalTransitions
        )
    }

    static func makeEvalRun(
        suiteName: String = "Test Suite",
        completedAt: Date? = Date(timeIntervalSince1970: 1_750_000_100),
        modelResults: [ModelEvalResult]? = nil
    ) -> EvalRun {
        EvalRun(
            suiteId: UUID(),
            suiteName: suiteName,
            suiteCategory: .general,
            startedAt: Date(timeIntervalSince1970: 1_750_000_000),
            completedAt: completedAt,
            platform: "macOS",
            deviceName: "Test Mac",
            modelResults: modelResults ?? [makeModelResult()]
        )
    }

    /// ISO-8601 encoder/decoder pair matching EvalResultPersistence's configuration.
    static func makeEncoderDecoder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (encoder, decoder)
    }

    /// Creates a temporary directory unique to the calling test.
    static func makeTempDir(label: String = "EvalPersistence") -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Removes a temporary directory if it exists.
    static func cleanupTempDir(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - EvalExportRecord Codable Tests

@Suite("EvalExportRecord Codable")
struct EvalExportRecordCodableTests {

    @Test("Round-trip preserves all fields from EvalRun")
    func roundTrip() throws {
        let run = TestFactory.makeEvalRun(
            suiteName: "Math Accuracy",
            completedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let record = EvalExportRecord(from: run)

        let (encoder, decoder) = TestFactory.makeEncoderDecoder()
        let data = try encoder.encode(record)
        let decoded = try decoder.decode(EvalExportRecord.self, from: data)

        #expect(decoded.exportVersion == "1.0")
        #expect(decoded.runId == run.id)
        #expect(decoded.suiteName == "Math Accuracy")
        #expect(decoded.suiteCategory == "general")
        #expect(decoded.platform == "macOS")
        #expect(decoded.deviceName == "Test Mac")
        #expect(decoded.overallPassRate == record.overallPassRate)
        #expect(decoded.modelCount == record.modelCount)
        #expect(decoded.totalPrompts == record.totalPrompts)
        #expect(decoded.completedAt != nil)
        #expect(decoded.models.count == 1)
        #expect(decoded.models[0].modelName == "Gemma 3n E2B")
    }

    @Test("Nil completedAt survives round-trip")
    func nilCompletedAt() throws {
        let run = TestFactory.makeEvalRun(completedAt: nil)
        let record = EvalExportRecord(from: run)

        let (encoder, decoder) = TestFactory.makeEncoderDecoder()
        let data = try encoder.encode(record)
        let decoded = try decoder.decode(EvalExportRecord.self, from: data)

        #expect(decoded.completedAt == nil)
    }

    @Test("Record captures correct aggregate metrics")
    func aggregateMetrics() {
        let passingPrompt = TestFactory.makePromptResult(passed: true)
        let failingPrompt = TestFactory.makePromptResult(
            passed: false, score: .fail(reason: "Wrong")
        )
        let model = TestFactory.makeModelResult(
            promptResults: [passingPrompt, failingPrompt]
        )
        let run = TestFactory.makeEvalRun(modelResults: [model])

        let record = EvalExportRecord(from: run)

        #expect(record.modelCount == 1)
        #expect(record.totalPrompts == 2)
        // 1 pass out of 2 total = 0.5
        #expect(record.overallPassRate == 0.5)
    }

    @Test("Decoding from raw JSON succeeds")
    func decodeFromRawJSON() throws {
        // Verify that the Codable conformance can handle externally-produced JSON
        let json = """
        {
            "exportVersion": "1.0",
            "exportedAt": "2026-06-18T20:00:00Z",
            "runId": "A1B2C3D4-E5F6-7890-ABCD-EF1234567890",
            "suiteName": "Raw JSON Suite",
            "suiteCategory": "reasoning",
            "platform": "iOS",
            "deviceName": "iPhone 16 Pro Max",
            "startedAt": "2026-06-18T19:50:00Z",
            "completedAt": "2026-06-18T20:00:00Z",
            "overallPassRate": 0.95,
            "modelCount": 2,
            "totalPrompts": 10,
            "models": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = Data(json.utf8)

        let record = try decoder.decode(EvalExportRecord.self, from: data)

        #expect(record.suiteName == "Raw JSON Suite")
        #expect(record.suiteCategory == "reasoning")
        #expect(record.platform == "iOS")
        #expect(record.overallPassRate == 0.95)
        #expect(record.models.isEmpty)
    }
}

// MARK: - ExportModelResult Codable Tests

@Suite("ExportModelResult Codable")
struct ExportModelResultCodableTests {

    @Test("Round-trip preserves all fields including optionals")
    func roundTrip() throws {
        let modelResult = TestFactory.makeModelResult(
            modelName: "Gemma 4 E4B",
            modelFile: "gemma-4-E4B-it.litertlm",
            toolCallAccuracy: 0.9,
            peakMemoryDeltaMB: 256.0,
            thermalTransitions: 2
        )
        let export = ExportModelResult(from: modelResult)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ExportModelResult.self, from: data)

        #expect(decoded.modelName == "Gemma 4 E4B")
        #expect(decoded.modelFile == "gemma-4-E4B-it.litertlm")
        #expect(decoded.passRate == export.passRate)
        #expect(decoded.avgDecodeSpeed == 40.0)
        #expect(decoded.avgTTFT == 0.88)
        #expect(decoded.p95Latency == 25.5)
        #expect(decoded.totalTokensGenerated == 500)
        #expect(decoded.totalDuration == 30.0)
        #expect(decoded.toolCallAccuracy == 0.9)
        #expect(decoded.peakMemoryDeltaMB == 256.0)
        #expect(decoded.thermalTransitions == 2)
        #expect(decoded.prompts.count == 2)
    }

    @Test("Nil optionals survive round-trip")
    func nilOptionals() throws {
        let modelResult = TestFactory.makeModelResult(
            toolCallAccuracy: nil,
            peakMemoryDeltaMB: nil
        )
        let export = ExportModelResult(from: modelResult)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ExportModelResult.self, from: data)

        #expect(decoded.toolCallAccuracy == nil)
        #expect(decoded.peakMemoryDeltaMB == nil)
    }

    @Test("Maps all fields correctly from ModelEvalResult")
    func mapsAllFields() {
        let modelResult = TestFactory.makeModelResult(
            modelName: "Test Model",
            modelFile: "test.litertlm",
            toolCallAccuracy: 0.85,
            peakMemoryDeltaMB: 300.0,
            thermalTransitions: 3
        )

        let export = ExportModelResult(from: modelResult)

        #expect(export.modelName == "Test Model")
        #expect(export.modelFile == "test.litertlm")
        #expect(export.passRate == modelResult.passRate)
        #expect(export.avgDecodeSpeed == modelResult.avgDecodeSpeed)
        #expect(export.avgTTFT == modelResult.avgTTFT)
        #expect(export.p95Latency == modelResult.p95Latency)
        #expect(export.totalTokensGenerated == modelResult.totalTokensGenerated)
        #expect(export.totalDuration == modelResult.totalDuration)
        #expect(export.toolCallAccuracy == 0.85)
        #expect(export.peakMemoryDeltaMB == 300.0)
        #expect(export.thermalTransitions == 3)
        #expect(export.prompts.count == modelResult.promptResults.count)
    }
}

// MARK: - ExportPromptScore Codable Tests

@Suite("ExportPromptScore Codable")
struct ExportPromptScoreCodableTests {

    @Test("Round-trip preserves all fields for passing prompt")
    func roundTripPassing() throws {
        let prompt = TestFactory.makePromptResult(
            promptText: "What is 2+2?",
            response: "The answer is 4.",
            passed: true,
            score: .pass,
            decodeSpeed: 42.0,
            ttft: 0.85,
            duration: 3.5
        )
        let export = ExportPromptScore(from: prompt)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ExportPromptScore.self, from: data)

        #expect(decoded.promptText == "What is 2+2?")
        #expect(decoded.response == "The answer is 4.")
        #expect(decoded.passed == true)
        #expect(decoded.scoreLabel == "Pass")
        #expect(decoded.scoreReason == nil)
        #expect(decoded.decodeSpeed == 42.0)
        #expect(decoded.ttft == 0.85)
        #expect(decoded.duration == 3.5)
        #expect(decoded.toolsCalled.isEmpty)
    }

    @Test("Round-trip preserves failing prompt with reason")
    func roundTripFailing() throws {
        let prompt = TestFactory.makePromptResult(
            passed: false,
            score: .fail(reason: "Expected exact value 3.333"),
            decodeSpeed: nil,
            ttft: nil,
            duration: 2.0
        )
        let export = ExportPromptScore(from: prompt)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ExportPromptScore.self, from: data)

        #expect(decoded.passed == false)
        #expect(decoded.scoreLabel == "Fail")
        #expect(decoded.scoreReason == "Expected exact value 3.333")
        #expect(decoded.decodeSpeed == nil)
        #expect(decoded.ttft == nil)
    }

    @Test("Round-trip preserves tool call names")
    func roundTripWithToolCalls() throws {
        let event = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expr\": \"2+2\"}",
            result: "4",
            durationMs: 10.0,
            timestamp: Date(),
            succeeded: true
        )
        let prompt = TestFactory.makePromptResult(toolCallEvents: [event])
        let export = ExportPromptScore(from: prompt)

        let data = try JSONEncoder().encode(export)
        let decoded = try JSONDecoder().decode(ExportPromptScore.self, from: data)

        #expect(decoded.toolsCalled == ["calculate"])
    }

    @Test("Maps score labels correctly for all score types",
          arguments: [
              (EvalScore.pass, "Pass"),
              (EvalScore.fail(reason: "Wrong"), "Fail"),
              (EvalScore.timeout, "Timeout"),
              (EvalScore.error("Crash"), "Error"),
              (EvalScore.manualReviewNeeded, "Needs Review"),
          ] as [(EvalScore, String)]
    )
    func scoreLabels(score: EvalScore, expectedLabel: String) {
        let prompt = TestFactory.makePromptResult(
            passed: score.isPass,
            score: score
        )
        let export = ExportPromptScore(from: prompt)

        #expect(export.scoreLabel == expectedLabel)
    }
}

// MARK: - ExportPromptScore Truncation Tests

@Suite("ExportPromptScore Response Truncation")
struct ExportPromptScoreTruncationTests {

    @Test("Response longer than 500 characters is truncated to 497 + ellipsis")
    func longResponseTruncated() {
        let longResponse = String(repeating: "A", count: 600)
        let prompt = TestFactory.makePromptResult(response: longResponse)

        let export = ExportPromptScore(from: prompt)

        #expect(export.response.count == 500)
        #expect(export.response.hasSuffix("..."))
        // First 497 characters should be the original content
        let prefix = String(export.response.prefix(497))
        #expect(prefix == String(repeating: "A", count: 497))
    }

    @Test("Response exactly 500 characters stays intact")
    func exactlyFiveHundredStaysIntact() {
        let exactResponse = String(repeating: "B", count: 500)
        let prompt = TestFactory.makePromptResult(response: exactResponse)

        let export = ExportPromptScore(from: prompt)

        #expect(export.response == exactResponse)
        #expect(export.response.count == 500)
    }

    @Test("Response shorter than 500 characters stays intact")
    func shortResponseStaysIntact() {
        let shortResponse = "Short answer."
        let prompt = TestFactory.makePromptResult(response: shortResponse)

        let export = ExportPromptScore(from: prompt)

        #expect(export.response == shortResponse)
    }

    @Test("Response exactly 501 characters is truncated")
    func boundaryTruncation() {
        let boundaryResponse = String(repeating: "C", count: 501)
        let prompt = TestFactory.makePromptResult(response: boundaryResponse)

        let export = ExportPromptScore(from: prompt)

        #expect(export.response.count == 500)
        #expect(export.response.hasSuffix("..."))
    }

    @Test("Empty response stays empty")
    func emptyResponse() {
        let prompt = TestFactory.makePromptResult(response: "")

        let export = ExportPromptScore(from: prompt)

        #expect(export.response == "")
    }
}

// MARK: - EvalResultPersistence Tests

@Suite("EvalResultPersistence")
@MainActor
struct EvalResultPersistenceTests {

    @Test("Init with custom directory creates directory on disk")
    func initCreatesDirectory() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceInit")
        defer { TestFactory.cleanupTempDir(tempDir) }

        // The subdir should not exist yet
        let subDir = tempDir.appendingPathComponent("exports")
        #expect(!FileManager.default.fileExists(atPath: subDir.path))

        let persistence = EvalResultPersistence(exportDirectory: subDir)

        #expect(persistence.exportDirectory == subDir)
        #expect(FileManager.default.fileExists(atPath: subDir.path))
    }

    @Test("Init with custom directory starts with empty state")
    func initEmptyHistory() {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceEmpty")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)

        #expect(persistence.exportHistory.isEmpty)
        #expect(persistence.lastExportURL == nil)
        #expect(persistence.lastExportStatus == "")
    }

    @Test("Save and load round-trip preserves run data")
    func saveAndLoadRoundTrip() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceSaveLoad")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let run = TestFactory.makeEvalRun(suiteName: "Round Trip Suite")

        let savedURL = try persistence.save(run)

        // Verify the file was created
        #expect(FileManager.default.fileExists(atPath: savedURL.path))

        // Verify observable state was updated
        #expect(persistence.lastExportURL == savedURL)
        #expect(persistence.lastExportStatus.contains("Exported"))
        #expect(persistence.exportHistory.count == 1)

        // Load and verify content
        let loaded = try persistence.load(from: savedURL)

        #expect(loaded.suiteName == "Round Trip Suite")
        #expect(loaded.suiteCategory == "general")
        #expect(loaded.platform == "macOS")
        #expect(loaded.deviceName == "Test Mac")
        #expect(loaded.runId == run.id)
        #expect(loaded.exportVersion == "1.0")
        #expect(loaded.models.count == 1)
        #expect(loaded.models[0].modelName == "Gemma 3n E2B")
        #expect(loaded.models[0].prompts.count == 2)
    }

    @Test("Save creates file with eval_results_ prefix and .json extension")
    func saveFilenameFormat() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceFilename")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let run = TestFactory.makeEvalRun()

        let savedURL = try persistence.save(run)

        #expect(savedURL.lastPathComponent.hasPrefix("eval_results_"))
        #expect(savedURL.pathExtension == "json")
    }

    @Test("Delete removes file from disk and updates history")
    func deleteRemovesFileAndUpdatesHistory() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceDelete")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let run = TestFactory.makeEvalRun()

        let savedURL = try persistence.save(run)
        #expect(persistence.exportHistory.count == 1)
        #expect(persistence.lastExportURL == savedURL)

        // Delete the file
        try persistence.delete(url: savedURL)

        #expect(!FileManager.default.fileExists(atPath: savedURL.path))
        #expect(persistence.exportHistory.isEmpty)
    }

    @Test("Delete updates lastExportURL to next in history")
    func deleteUpdatesLastExportURL() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceDeleteMulti")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)

        // Save two runs with different completedAt timestamps
        let run1 = TestFactory.makeEvalRun(
            suiteName: "First",
            completedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let url1 = try persistence.save(run1)

        let run2 = TestFactory.makeEvalRun(
            suiteName: "Second",
            completedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )
        let url2 = try persistence.save(run2)

        #expect(persistence.exportHistory.count == 2)

        // Delete the most recent (url2, which was inserted at index 0)
        try persistence.delete(url: url2)

        #expect(persistence.exportHistory.count == 1)
        #expect(persistence.lastExportURL == url1)
    }

    @Test("Delete nonexistent file throws EvalExportError")
    func deleteNonexistentThrows() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceDeleteFail")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let fakeURL = tempDir.appendingPathComponent("nonexistent.json")

        #expect(throws: EvalExportError.self) {
            try persistence.delete(url: fakeURL)
        }
    }

    @Test("Load from nonexistent URL throws EvalExportError")
    func loadNonexistentThrows() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceLoadFail")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let fakeURL = tempDir.appendingPathComponent("nonexistent.json")

        #expect(throws: EvalExportError.self) {
            try persistence.load(from: fakeURL)
        }
    }

    @Test("New instance discovers existing export files on init")
    func loadExportHistoryFindsFiles() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceHistory")
        defer { TestFactory.cleanupTempDir(tempDir) }

        // Pre-populate the directory with valid export files
        let persistence1 = EvalResultPersistence(exportDirectory: tempDir)
        let run1 = TestFactory.makeEvalRun(
            suiteName: "History Run 1",
            completedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let run2 = TestFactory.makeEvalRun(
            suiteName: "History Run 2",
            completedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )
        try persistence1.save(run1)
        try persistence1.save(run2)

        // Create a new persistence instance — it should discover the files on init
        let persistence2 = EvalResultPersistence(exportDirectory: tempDir)

        #expect(persistence2.exportHistory.count == 2)
        #expect(persistence2.lastExportURL != nil)

        // History should be sorted newest-first (by filename descending)
        let firstFilename = persistence2.exportHistory[0].lastPathComponent
        let secondFilename = persistence2.exportHistory[1].lastPathComponent
        #expect(firstFilename > secondFilename)
    }

    @Test("loadExportHistory ignores non-export files")
    func loadExportHistoryIgnoresOtherFiles() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceIgnore")
        defer { TestFactory.cleanupTempDir(tempDir) }

        // Create files that should NOT be discovered:
        // 1. A JSON file without the eval_results_ prefix
        let otherJSON = tempDir.appendingPathComponent("other_data.json")
        try Data("{}".utf8).write(to: otherJSON)

        // 2. A non-JSON file with the export prefix
        let textFile = tempDir.appendingPathComponent("eval_results_note.txt")
        try Data("note".utf8).write(to: textFile)

        // Create one valid export file
        let persistence1 = EvalResultPersistence(exportDirectory: tempDir)
        try persistence1.save(TestFactory.makeEvalRun())

        // Re-init to trigger fresh history scanning
        let persistence2 = EvalResultPersistence(exportDirectory: tempDir)

        // Should only find the one valid export file (eval_results_ prefix + .json extension)
        #expect(persistence2.exportHistory.count == 1)
    }

    @Test("Multiple saves produce distinct files and accumulate history")
    func multipleSavesDistinctFiles() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceMultiple")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)

        let run1 = TestFactory.makeEvalRun(
            suiteName: "Run A",
            completedAt: Date(timeIntervalSince1970: 1_750_000_100)
        )
        let run2 = TestFactory.makeEvalRun(
            suiteName: "Run B",
            completedAt: Date(timeIntervalSince1970: 1_750_000_200)
        )

        let url1 = try persistence.save(run1)
        let url2 = try persistence.save(run2)

        #expect(url1 != url2)
        #expect(persistence.exportHistory.count == 2)
        #expect(persistence.lastExportURL == url2)
    }

    @Test("Saved JSON is valid and contains expected keys")
    func savedJSONContainsExpectedKeys() throws {
        let tempDir = TestFactory.makeTempDir(label: "PersistenceJSON")
        defer { TestFactory.cleanupTempDir(tempDir) }

        let persistence = EvalResultPersistence(exportDirectory: tempDir)
        let run = TestFactory.makeEvalRun(suiteName: "JSON Validation")

        let savedURL = try persistence.save(run)
        let data = try Data(contentsOf: savedURL)
        let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let json = try #require(jsonObject)

        #expect(json["exportVersion"] as? String == "1.0")
        #expect(json["suiteName"] as? String == "JSON Validation")
        #expect(json["platform"] as? String == "macOS")
        #expect(json["models"] is [[String: Any]])
    }
}

// MARK: - EvalExportError Tests

@Suite("EvalExportError")
struct EvalExportErrorTests {

    @Test("saveFailed includes 'save' and underlying message in description")
    func saveFailedDescription() {
        let underlying = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "Disk full",
        ])
        let error = EvalExportError.saveFailed(underlying)

        let description = error.errorDescription ?? ""
        #expect(description.localizedCaseInsensitiveContains("save"))
        #expect(description.contains("Disk full"))
    }

    @Test("loadFailed includes 'load' and underlying message in description")
    func loadFailedDescription() {
        let underlying = NSError(domain: "TestDomain", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "File not found",
        ])
        let error = EvalExportError.loadFailed(underlying)

        let description = error.errorDescription ?? ""
        #expect(description.localizedCaseInsensitiveContains("load"))
        #expect(description.contains("File not found"))
    }

    @Test("deleteFailed includes 'delete' and underlying message in description")
    func deleteFailedDescription() {
        let underlying = NSError(domain: "TestDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Permission denied",
        ])
        let error = EvalExportError.deleteFailed(underlying)

        let description = error.errorDescription ?? ""
        #expect(description.localizedCaseInsensitiveContains("delete"))
        #expect(description.contains("Permission denied"))
    }
}
