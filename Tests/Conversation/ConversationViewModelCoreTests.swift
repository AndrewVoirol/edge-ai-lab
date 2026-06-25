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

// MARK: - Conversation ViewModel Core Tests
//
// Tests the data-layer types used by ConversationViewModel that are NOT
// covered by ChatMessageSwiftTestingTests, SavedConversationTests,
// ExperimentConfigTests, or ExperimentalFlagsStateTests.
//
// Focus areas:
// - ChatMessage Codable round-trips (including nested types)
// - ChatMessage.Attachment metadata-only encoding
// - ChatMessage.BenchmarkSnapshot Codable
// - ChatMessage.SpecialResult Codable
// - ChatMessage.Role raw values and Codable
// - ConversationState Codable and advanced update paths
// - ToolCallEvent Codable
// - InstrumentedEngineError descriptions
// - BackendResult.ActiveBackend raw values

// MARK: - ChatMessage.Role

@Suite("ChatMessage.Role")
struct ChatMessageRoleTests {

    @Test(
        "Raw values match expected strings",
        arguments: [
            (ChatMessage.Role.user, "user"),
            (ChatMessage.Role.assistant, "assistant"),
            (ChatMessage.Role.system, "system"),
            (ChatMessage.Role.toolResult, "toolResult"),
        ] as [(ChatMessage.Role, String)]
    )
    func rawValues(role: ChatMessage.Role, expected: String) {
        #expect(role.rawValue == expected)
    }

    @Test(
        "Round-trip Codable preserves each role",
        arguments: [
            ChatMessage.Role.user,
            ChatMessage.Role.assistant,
            ChatMessage.Role.system,
            ChatMessage.Role.toolResult,
        ]
    )
    func codableRoundTrip(role: ChatMessage.Role) throws {
        let data = try JSONEncoder().encode(role)
        let decoded = try JSONDecoder().decode(ChatMessage.Role.self, from: data)
        #expect(decoded == role)
    }

    @Test("Initializing from raw value succeeds for known values")
    func initFromRawValue() {
        #expect(ChatMessage.Role(rawValue: "user") == .user)
        #expect(ChatMessage.Role(rawValue: "assistant") == .assistant)
        #expect(ChatMessage.Role(rawValue: "system") == .system)
        #expect(ChatMessage.Role(rawValue: "toolResult") == .toolResult)
    }

    @Test("Initializing from unknown raw value returns nil")
    func initFromUnknownRawValue() {
        #expect(ChatMessage.Role(rawValue: "moderator") == nil)
        #expect(ChatMessage.Role(rawValue: "") == nil)
    }
}

// MARK: - ChatMessage.Attachment Codable

@Suite("ChatMessage.Attachment Codable")
struct ChatMessageAttachmentCodableTests {

    @Test("Image attachment encodes type and size, not binary data")
    func imageAttachmentEncodesMetadataOnly() throws {
        let imageData = Data(repeating: 0xAB, count: 1024)
        let attachment = ChatMessage.Attachment.image(imageData)

        let encoded = try JSONEncoder().encode(attachment)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["type"] as? String == "image")
        #expect(json["sizeBytes"] as? Int == 1024)
        // The note should mention the size
        let note = json["note"] as? String
        #expect(note != nil)
        #expect(note?.contains("Image") == true)
    }

    @Test("Audio attachment encodes type and size, not binary data")
    func audioAttachmentEncodesMetadataOnly() throws {
        let audioData = Data(repeating: 0xCD, count: 2048)
        let attachment = ChatMessage.Attachment.audio(audioData)

        let encoded = try JSONEncoder().encode(attachment)
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

        #expect(json["type"] as? String == "audio")
        #expect(json["sizeBytes"] as? Int == 2048)
        let note = json["note"] as? String
        #expect(note != nil)
        #expect(note?.contains("Audio") == true)
    }

    @Test("Image attachment decodes with empty data (metadata only)")
    func imageAttachmentDecodesWithEmptyData() throws {
        let original = ChatMessage.Attachment.image(Data([1, 2, 3, 4, 5]))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: encoded)

        // After round-trip, binary data is lost (by design) — decoded as empty
        #expect(decoded.isImage)
        #expect(!decoded.isAudio)
    }

    @Test("Audio attachment decodes with empty data (metadata only)")
    func audioAttachmentDecodesWithEmptyData() throws {
        let original = ChatMessage.Attachment.audio(Data([10, 20, 30]))

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: encoded)

        #expect(decoded.isAudio)
        #expect(!decoded.isImage)
    }

    @Test("Unknown type decodes as image fallback")
    func unknownTypeDecodesAsImageFallback() throws {
        let json = """
        {"type": "video", "sizeBytes": 100, "note": "test"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: json)
        // Unknown types fall back to .image per the decoder implementation
        #expect(decoded.isImage)
    }
}

// MARK: - ChatMessage.BenchmarkSnapshot Codable

@Suite("ChatMessage.BenchmarkSnapshot")
struct BenchmarkSnapshotTests {

    @Test("Round-trip Codable preserves all fields")
    func codableRoundTrip() throws {
        let original = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 42.5,
            timeToFirstToken: 0.123,
            tokenCount: 256
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.BenchmarkSnapshot.self, from: data)

        #expect(decoded.decodeTokensPerSecond == 42.5)
        #expect(decoded.timeToFirstToken == 0.123)
        #expect(decoded.tokenCount == 256)
    }

    @Test("Encodes with correct JSON keys")
    func jsonKeys() throws {
        let snapshot = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 10.0,
            timeToFirstToken: 0.5,
            tokenCount: 100
        )

        let data = try JSONEncoder().encode(snapshot)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        #expect(json.keys.contains("decodeTokensPerSecond"))
        #expect(json.keys.contains("timeToFirstToken"))
        #expect(json.keys.contains("tokenCount"))
    }

    @Test("Zero values round-trip correctly")
    func zeroValues() throws {
        let original = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 0.0,
            timeToFirstToken: 0.0,
            tokenCount: 0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.BenchmarkSnapshot.self, from: data)

        #expect(decoded.decodeTokensPerSecond == 0.0)
        #expect(decoded.timeToFirstToken == 0.0)
        #expect(decoded.tokenCount == 0)
    }
}

// MARK: - ChatMessage.SpecialResult Codable

@Suite("ChatMessage.SpecialResult")
struct SpecialResultTests {

    @Test("Round-trip Codable with all fields set")
    func codableRoundTripAllFields() throws {
        let original = ChatMessage.SpecialResult(
            type: "wikipedia",
            query: "quantum computing",
            title: "Quantum Computing",
            extract: "A quantum computer is...",
            url: "https://en.wikipedia.org/wiki/Quantum_computing",
            thumbnail_url: "https://upload.wikimedia.org/thumb.jpg",
            latitude: 37.7749,
            longitude: -122.4194,
            subtitle: "Technology"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: data)

        #expect(decoded.type == "wikipedia")
        #expect(decoded.query == "quantum computing")
        #expect(decoded.title == "Quantum Computing")
        #expect(decoded.extract == "A quantum computer is...")
        #expect(decoded.url == "https://en.wikipedia.org/wiki/Quantum_computing")
        #expect(decoded.thumbnail_url == "https://upload.wikimedia.org/thumb.jpg")
        #expect(decoded.latitude == 37.7749)
        #expect(decoded.longitude == -122.4194)
        #expect(decoded.subtitle == "Technology")
    }

    @Test("Round-trip Codable with nil optional fields")
    func codableRoundTripNilFields() throws {
        let original = ChatMessage.SpecialResult(
            type: "maps",
            query: nil,
            title: nil,
            extract: nil,
            url: nil,
            thumbnail_url: nil,
            latitude: nil,
            longitude: nil,
            subtitle: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: data)

        #expect(decoded.type == "maps")
        #expect(decoded.query == nil)
        #expect(decoded.title == nil)
        #expect(decoded.extract == nil)
        #expect(decoded.url == nil)
        #expect(decoded.thumbnail_url == nil)
        #expect(decoded.latitude == nil)
        #expect(decoded.longitude == nil)
        #expect(decoded.subtitle == nil)
    }

    @Test("Decodes from partial JSON with only required field")
    func decodesFromPartialJSON() throws {
        let json = """
        {"type": "wikipedia"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: json)
        #expect(decoded.type == "wikipedia")
        #expect(decoded.query == nil)
        #expect(decoded.latitude == nil)
    }
}

// MARK: - ChatMessage Codable (Full Message)

@Suite("ChatMessage Codable")
struct ChatMessageCodableTests {

    @Test("User message round-trips with content and metadata")
    func userMessageRoundTrip() throws {
        let original = ChatMessage.user("Hello, world!")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.role == .user)
        #expect(decoded.content == "Hello, world!")
        #expect(decoded.isStreaming == false)
        #expect(decoded.attachments.isEmpty)
        #expect(decoded.toolCalls.isEmpty)
        #expect(decoded.thinkingContent == nil)
        #expect(decoded.benchmarkInfo == nil)
    }

    @Test("Assistant message round-trips with thinking content")
    func assistantMessageWithThinkingRoundTrip() throws {
        var original = ChatMessage.assistant("The answer is 42.")
        original.thinkingContent = "Let me reason about this..."
        original.thinkingWordCount = 5

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.role == .assistant)
        #expect(decoded.content == "The answer is 42.")
        #expect(decoded.thinkingContent == "Let me reason about this...")
        #expect(decoded.thinkingWordCount == 5)
    }

    @Test("Message with benchmark info round-trips")
    func messageWithBenchmarkRoundTrip() throws {
        var original = ChatMessage.assistant("Response text")
        original.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 55.3,
            timeToFirstToken: 0.2,
            tokenCount: 150
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.benchmarkInfo != nil)
        #expect(decoded.benchmarkInfo?.decodeTokensPerSecond == 55.3)
        #expect(decoded.benchmarkInfo?.tokenCount == 150)
    }

    @Test("Message with image attachment round-trips (metadata only)")
    func messageWithAttachmentRoundTrip() throws {
        let original = ChatMessage.user("Look at this", imageData: Data(repeating: 0xFF, count: 512))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.role == .user)
        #expect(decoded.content == "Look at this")
        #expect(decoded.attachments.count == 1)
        // After round-trip, attachment type is preserved but binary data is lost
        #expect(decoded.attachments.first?.isImage == true)
    }

    @Test("Message with both image and audio attachments round-trips")
    func messageWithMultipleAttachments() throws {
        let original = ChatMessage.user(
            "Multimodal",
            imageData: Data([1, 2, 3]),
            audioData: Data([4, 5, 6])
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.attachments.count == 2)
        #expect(decoded.attachments[0].isImage)
        #expect(decoded.attachments[1].isAudio)
    }

    @Test("Message with special results round-trips")
    func messageWithSpecialResults() throws {
        let specialId = UUID()
        var original = ChatMessage.assistant("Here's what I found.")
        original.specialResults[specialId] = ChatMessage.SpecialResult(
            type: "wikipedia",
            query: "Swift language",
            title: "Swift (programming language)",
            extract: "Swift is a compiled language...",
            url: "https://en.wikipedia.org/wiki/Swift_(programming_language)",
            thumbnail_url: nil,
            latitude: nil,
            longitude: nil,
            subtitle: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ChatMessage.self, from: data)

        #expect(decoded.specialResults.count == 1)
        let result = decoded.specialResults[specialId]
        #expect(result?.type == "wikipedia")
        #expect(result?.title == "Swift (programming language)")
    }
}

// MARK: - ConversationState Advanced Updates

@Suite("ConversationState Advanced Updates")
struct ConversationStateAdvancedTests {

    @Test("updateLastAssistantMessage with thinking content sets thinkingWordCount")
    func updateWithThinkingContent() {
        var state = ConversationState()
        state.append(.user("What is 2+2?"))
        state.append(.assistant())

        state.updateLastAssistantMessage(
            content: "4",
            thinkingContent: "I need to add two and two together"
        )

        #expect(state.lastMessage?.content == "4")
        #expect(state.lastMessage?.thinkingContent == "I need to add two and two together")
        #expect(state.lastMessage?.thinkingWordCount == 8)
    }

    @Test("updateLastAssistantMessage with benchmark info stores snapshot")
    func updateWithBenchmarkInfo() {
        var state = ConversationState()
        state.append(.user("Hi"))
        state.append(.assistant())

        let benchmark = ChatMessage.BenchmarkSnapshot(
            decodeTokensPerSecond: 42.0,
            timeToFirstToken: 0.1,
            tokenCount: 200
        )
        state.updateLastAssistantMessage(benchmarkInfo: benchmark)

        #expect(state.lastMessage?.benchmarkInfo?.decodeTokensPerSecond == 42.0)
        #expect(state.lastMessage?.benchmarkInfo?.tokenCount == 200)
    }

    @Test("updateLastAssistantMessage with tool calls stores events")
    func updateWithToolCalls() {
        var state = ConversationState()
        state.append(.user("Calculate something"))
        state.append(.assistant())

        let toolCall = ToolCallEvent(
            toolName: "calculator",
            arguments: "{\"a\": 1, \"b\": 2}",
            result: "{\"sum\": 3}",
            durationMs: 5.0,
            timestamp: Date(),
            succeeded: true
        )
        state.updateLastAssistantMessage(toolCalls: [toolCall])

        #expect(state.lastMessage?.toolCalls.count == 1)
        #expect(state.lastMessage?.toolCalls.first?.toolName == "calculator")
    }

    @Test("updateLastAssistantMessage is a no-op when last message is not assistant")
    func updateNoOpWhenLastIsUser() {
        var state = ConversationState()
        state.append(.user("Hello"))

        // This should not crash or modify anything
        state.updateLastAssistantMessage(content: "Should not appear")

        #expect(state.lastMessage?.role == .user)
        #expect(state.lastMessage?.content == "Hello")
    }

    @Test("updateLastAssistantMessage is a no-op on empty conversation")
    func updateNoOpWhenEmpty() {
        var state = ConversationState()

        // Should not crash
        state.updateLastAssistantMessage(content: "Nothing here")
        #expect(state.isEmpty)
    }

    @Test("updateLastAssistantMessage with tool call result populates specialResults")
    func toolCallResultPopulatesSpecialResults() {
        var state = ConversationState()
        state.append(.user("Tell me about Paris"))
        state.append(.assistant())

        let wikiJSON = """
        {"type": "wikipedia", "query": "Paris", "title": "Paris", "extract": "Capital of France"}
        """
        let toolCall = ToolCallEvent(
            toolName: "wikipedia_search",
            arguments: "{\"query\": \"Paris\"}",
            result: wikiJSON,
            durationMs: 50.0,
            timestamp: Date(),
            succeeded: true
        )
        state.updateLastAssistantMessage(toolCalls: [toolCall])

        // The update method should decode the tool result as a SpecialResult
        #expect(state.lastMessage?.specialResults.count == 1)
        let special = state.lastMessage?.specialResults.values.first
        #expect(special?.type == "wikipedia")
        #expect(special?.title == "Paris")
    }

    @Test("Multiple streaming updates accumulate content correctly")
    func multipleStreamingUpdates() {
        var state = ConversationState()
        state.append(.user("Tell me a story"))
        state.append(.assistant())

        state.updateLastAssistantMessage(content: "Once upon ")
        #expect(state.lastMessage?.content == "Once upon ")

        state.updateLastAssistantMessage(content: "Once upon a time ")
        #expect(state.lastMessage?.content == "Once upon a time ")

        state.updateLastAssistantMessage(content: "Once upon a time there was a model.", isStreaming: false)
        #expect(state.lastMessage?.content == "Once upon a time there was a model.")
        #expect(state.lastMessage?.isStreaming == false)
    }
}

// MARK: - ConversationState Codable

@Suite("ConversationState Codable")
struct ConversationStateCodableTests {

    @Test("Empty conversation state round-trips")
    func emptyStateRoundTrip() throws {
        let original = ConversationState()

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversationState.self, from: data)

        #expect(decoded.isEmpty)
        #expect(decoded.count == 0)
    }

    @Test("Conversation state with messages round-trips")
    func stateWithMessagesRoundTrip() throws {
        var original = ConversationState()
        original.append(.user("Hello"))
        original.append(.assistant("Hi there!"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ConversationState.self, from: data)

        #expect(decoded.count == 2)
        #expect(decoded.messages[0].role == .user)
        #expect(decoded.messages[0].content == "Hello")
        #expect(decoded.messages[1].role == .assistant)
        #expect(decoded.messages[1].content == "Hi there!")
    }

    @Test("lastMessage returns correct message after round-trip")
    func lastMessageAfterRoundTrip() throws {
        var original = ConversationState()
        original.append(.user("First"))
        original.append(.user("Second"))
        original.append(.assistant("Third"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ConversationState.self, from: data)

        #expect(decoded.lastMessage?.content == "Third")
        #expect(decoded.lastMessage?.role == .assistant)
    }
}

// MARK: - ToolCallEvent Codable

@Suite("ToolCallEvent Codable")
struct ToolCallEventCodableTests {

    @Test("Round-trip preserves all fields")
    func codableRoundTrip() throws {
        let now = Date()
        let original = ToolCallEvent(
            toolName: "calculator",
            arguments: "{\"expression\": \"2+2\"}",
            result: "{\"answer\": 4}",
            durationMs: 12.5,
            timestamp: now,
            succeeded: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ToolCallEvent.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.toolName == "calculator")
        #expect(decoded.arguments == "{\"expression\": \"2+2\"}")
        #expect(decoded.result == "{\"answer\": 4}")
        #expect(decoded.durationMs == 12.5)
        #expect(decoded.succeeded == true)
        // Date comparison: allow sub-millisecond rounding from JSON
        #expect(abs(decoded.timestamp.timeIntervalSince(now)) < 1.0)
    }

    @Test("Failed tool call round-trips correctly")
    func failedToolCallRoundTrip() throws {
        let original = ToolCallEvent(
            toolName: "network_fetch",
            arguments: "{\"url\": \"https://example.com\"}",
            result: "Error: connection refused",
            durationMs: 5000.0,
            timestamp: Date(),
            succeeded: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(ToolCallEvent.self, from: data)

        #expect(decoded.succeeded == false)
        #expect(decoded.toolName == "network_fetch")
        #expect(decoded.result == "Error: connection refused")
    }

    @Test("Multiple tool call events encode as JSON array")
    func multipleEventsEncodeAsArray() throws {
        let events = [
            ToolCallEvent(toolName: "tool_a", arguments: "{}", result: "ok", durationMs: 1.0, timestamp: Date(), succeeded: true),
            ToolCallEvent(toolName: "tool_b", arguments: "{}", result: "ok", durationMs: 2.0, timestamp: Date(), succeeded: true),
            ToolCallEvent(toolName: "tool_c", arguments: "{}", result: "err", durationMs: 3.0, timestamp: Date(), succeeded: false),
        ]

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(events)
        let decoded = try decoder.decode([ToolCallEvent].self, from: data)

        #expect(decoded.count == 3)
        #expect(decoded[0].toolName == "tool_a")
        #expect(decoded[2].succeeded == false)
    }
}

// MARK: - InstrumentedEngineError

@Suite("InstrumentedEngineError")
struct InstrumentedEngineErrorTests {

    @Test("notInitialized has descriptive error message")
    func notInitializedDescription() {
        let error = InstrumentedEngineError.notInitialized
        let description = error.errorDescription ?? ""
        #expect(description.contains("not initialized"))
    }

    @Test("bothBackendsFailed includes both backend names and errors")
    func bothBackendsFailedDescription() {
        let error = InstrumentedEngineError.bothBackendsFailed(
            primaryBackend: "GPU",
            primaryError: "Metal not available",
            fallbackBackend: "CPU",
            fallbackError: "Out of memory"
        )
        let description = error.errorDescription ?? ""
        #expect(description.contains("GPU"))
        #expect(description.contains("Metal not available"))
        #expect(description.contains("CPU"))
        #expect(description.contains("Out of memory"))
    }

    @Test("bothBackendsFailed conforms to LocalizedError")
    func conformsToLocalizedError() {
        let error: any LocalizedError = InstrumentedEngineError.notInitialized
        #expect(error.errorDescription != nil)
    }
}

// MARK: - BackendResult.ActiveBackend

@Suite("BackendResult.ActiveBackend")
struct ActiveBackendTests {

    @Test("GPU raw value is 'gpu'")
    func gpuRawValue() {
        #expect(BackendResult.ActiveBackend.gpu.rawValue == "gpu")
    }

    @Test("CPU raw value is 'cpu'")
    func cpuRawValue() {
        #expect(BackendResult.ActiveBackend.cpu.rawValue == "cpu")
    }

    @Test("Initializing from raw value succeeds")
    func initFromRawValue() {
        #expect(BackendResult.ActiveBackend(rawValue: "gpu") == .gpu)
        #expect(BackendResult.ActiveBackend(rawValue: "cpu") == .cpu)
    }

    @Test("Initializing from unknown raw value returns nil")
    func initFromUnknownRawValue() {
        #expect(BackendResult.ActiveBackend(rawValue: "tpu") == nil)
        #expect(BackendResult.ActiveBackend(rawValue: "GPU") == nil)
    }
}
