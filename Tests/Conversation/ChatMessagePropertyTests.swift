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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - ChatMessage Property Tests

@Suite("ChatMessage Properties")
struct ChatMessagePropertySwiftTests {

    // MARK: - Role Enum

    @Suite("Role Enum")
    struct RoleTests {

        @Test("Raw values match expected strings",
              arguments: [
                  (ChatMessage.Role.user, "user"),
                  (ChatMessage.Role.assistant, "assistant"),
                  (ChatMessage.Role.system, "system"),
                  (ChatMessage.Role.toolResult, "toolResult"),
              ] as [(ChatMessage.Role, String)])
        func rawValues(role: ChatMessage.Role, expected: String) {
            #expect(role.rawValue == expected)
        }

        @Test("Round-trip through rawValue preserves identity",
              arguments: [
                  ChatMessage.Role.user,
                  ChatMessage.Role.assistant,
                  ChatMessage.Role.system,
                  ChatMessage.Role.toolResult,
              ])
        func rawValueRoundTrip(role: ChatMessage.Role) {
            let recreated = ChatMessage.Role(rawValue: role.rawValue)
            #expect(recreated == role)
        }

        @Test("Invalid rawValue returns nil")
        func invalidRawValue() {
            #expect(ChatMessage.Role(rawValue: "admin") == nil)
            #expect(ChatMessage.Role(rawValue: "") == nil)
        }

        @Test("Role conforms to Codable via JSON round-trip",
              arguments: [
                  ChatMessage.Role.user,
                  ChatMessage.Role.assistant,
                  ChatMessage.Role.system,
                  ChatMessage.Role.toolResult,
              ])
        func roleCodableRoundTrip(role: ChatMessage.Role) throws {
            let data = try JSONEncoder().encode(role)
            let decoded = try JSONDecoder().decode(ChatMessage.Role.self, from: data)
            #expect(decoded == role)
        }
    }

    // MARK: - Attachment Properties

    @Suite("Attachment Properties")
    struct AttachmentTests {

        @Test("Image attachment isImage returns true, isAudio returns false")
        func imageAttachment() {
            let attachment = ChatMessage.Attachment.image(Data([0xFF, 0xD8, 0xFF]))
            #expect(attachment.isImage)
            #expect(!attachment.isAudio)
        }

        @Test("Audio attachment isAudio returns true, isImage returns false")
        func audioAttachment() {
            let attachment = ChatMessage.Attachment.audio(Data([0x00, 0x01, 0x02]))
            #expect(attachment.isAudio)
            #expect(!attachment.isImage)
        }

        @Test("Image attachment encodes type and sizeBytes metadata")
        func imageAttachmentEncoding() throws {
            let imageData = Data(repeating: 0xAB, count: 1024)
            let attachment = ChatMessage.Attachment.image(imageData)

            let encoded = try JSONEncoder().encode(attachment)
            let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

            #expect(json["type"] as? String == "image")
            #expect(json["sizeBytes"] as? Int == 1024)

            // Note field should contain "Image:" and a size unit
            let note = json["note"] as? String ?? ""
            #expect(note.contains("Image:"))
        }

        @Test("Audio attachment encodes type and sizeBytes metadata")
        func audioAttachmentEncoding() throws {
            let audioData = Data(repeating: 0xCD, count: 2048)
            let attachment = ChatMessage.Attachment.audio(audioData)

            let encoded = try JSONEncoder().encode(attachment)
            let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]

            #expect(json["type"] as? String == "audio")
            #expect(json["sizeBytes"] as? Int == 2048)

            let note = json["note"] as? String ?? ""
            #expect(note.contains("Audio:"))
        }

        @Test("Decoding restores type but with empty data (metadata-only persistence)")
        func attachmentDecodingRestoresTypeOnly() throws {
            // Encode an image with real data
            let original = ChatMessage.Attachment.image(Data(repeating: 0xFF, count: 512))
            let encoded = try JSONEncoder().encode(original)

            // Decode — data should be empty, but type should be preserved
            let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: encoded)
            #expect(decoded.isImage)
            #expect(!decoded.isAudio)
        }

        @Test("Decoding audio JSON restores audio type")
        func audioDecodingRestoresType() throws {
            let original = ChatMessage.Attachment.audio(Data(repeating: 0x00, count: 256))
            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: encoded)
            #expect(decoded.isAudio)
            #expect(!decoded.isImage)
        }

        @Test("Decoding unknown type falls back to image")
        func unknownTypeFallsBackToImage() throws {
            let json = """
            {"type": "video", "sizeBytes": 100, "note": "[Video: 100 bytes]"}
            """.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(ChatMessage.Attachment.self, from: json)
            #expect(decoded.isImage)
        }
    }

    // MARK: - BenchmarkSnapshot

    @Suite("BenchmarkSnapshot")
    struct BenchmarkSnapshotTests {

        @Test("Direct initializer preserves all values")
        func directInit() {
            let snap = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 42.5,
                timeToFirstToken: 0.123,
                tokenCount: 100
            )
            #expect(snap.decodeTokensPerSecond == 42.5)
            #expect(snap.timeToFirstToken == 0.123)
            #expect(snap.tokenCount == 100)
        }

        @Test("Codable round-trip preserves values")
        func codableRoundTrip() throws {
            let snap = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 55.0,
                timeToFirstToken: 0.250,
                tokenCount: 200
            )
            let data = try JSONEncoder().encode(snap)
            let decoded = try JSONDecoder().decode(ChatMessage.BenchmarkSnapshot.self, from: data)
            #expect(decoded.decodeTokensPerSecond == snap.decodeTokensPerSecond)
            #expect(decoded.timeToFirstToken == snap.timeToFirstToken)
            #expect(decoded.tokenCount == snap.tokenCount)
        }

        @Test("Zero values are valid")
        func zeroValues() {
            let snap = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 0.0,
                timeToFirstToken: 0.0,
                tokenCount: 0
            )
            #expect(snap.decodeTokensPerSecond == 0.0)
            #expect(snap.tokenCount == 0)
        }
    }

    // MARK: - SpecialResult

    @Suite("SpecialResult")
    struct SpecialResultTests {

        @Test("Codable round-trip preserves all fields")
        func codableRoundTrip() throws {
            let json = """
            {
                "type": "wikipedia",
                "query": "Swift programming",
                "title": "Swift (programming language)",
                "extract": "Swift is a compiled language...",
                "url": "https://en.wikipedia.org/wiki/Swift_(programming_language)",
                "thumbnail_url": "https://example.com/thumb.png",
                "latitude": null,
                "longitude": null,
                "subtitle": null
            }
            """.data(using: .utf8)!

            let result = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: json)
            #expect(result.type == "wikipedia")
            #expect(result.query == "Swift programming")
            #expect(result.title == "Swift (programming language)")
            #expect(result.extract?.contains("compiled") == true)
            #expect(result.url?.contains("wikipedia") == true)
            #expect(result.thumbnail_url != nil)
            #expect(result.latitude == nil)
            #expect(result.longitude == nil)
            #expect(result.subtitle == nil)
        }

        @Test("Maps result with coordinates round-trips")
        func mapsResultRoundTrip() throws {
            let json = """
            {
                "type": "maps",
                "query": "coffee shops",
                "title": "Blue Bottle Coffee",
                "extract": null,
                "url": null,
                "thumbnail_url": null,
                "latitude": 37.7749,
                "longitude": -122.4194,
                "subtitle": "Specialty Coffee"
            }
            """.data(using: .utf8)!

            let result = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: json)
            #expect(result.type == "maps")
            #expect(result.latitude == 37.7749)
            #expect(result.longitude == -122.4194)
            #expect(result.subtitle == "Specialty Coffee")
        }

        @Test("Minimal result with only required type field")
        func minimalResult() throws {
            let json = """
            {"type": "unknown"}
            """.data(using: .utf8)!

            let result = try JSONDecoder().decode(ChatMessage.SpecialResult.self, from: json)
            #expect(result.type == "unknown")
            #expect(result.query == nil)
            #expect(result.title == nil)
        }
    }

    // MARK: - ThinkingWordCount

    @Suite("ThinkingWordCount")
    struct ThinkingWordCountTests {

        @Test("Default thinkingWordCount is zero for factory messages",
              arguments: ["user", "assistant", "system"])
        func defaultThinkingWordCountIsZero(role: String) {
            let msg: ChatMessage
            switch role {
            case "user": msg = .user("Hello")
            case "assistant": msg = .assistant()
            case "system": msg = .system("Be helpful")
            default: fatalError("Unknown role")
            }
            #expect(msg.thinkingWordCount == 0)
        }

        @Test("ThinkingWordCount is mutable and reflects assigned value")
        func mutableThinkingWordCount() {
            var msg = ChatMessage.assistant()
            msg.thinkingWordCount = 42
            #expect(msg.thinkingWordCount == 42)
        }

        @Test("ConversationState.updateLastAssistantMessage sets thinkingWordCount from thinkingContent")
        func updateSetsWordCountFromContent() {
            var state = ConversationState()
            state.append(.user("Hi"))
            state.append(.assistant())

            let thinkingText = "Let me think about this problem step by step"
            state.updateLastAssistantMessage(thinkingContent: thinkingText)

            let expectedWordCount = thinkingText.split(separator: " ").count
            #expect(state.lastMessage?.thinkingWordCount == expectedWordCount)
            #expect(state.lastMessage?.thinkingContent == thinkingText)
        }
    }

    // MARK: - ChatMessage Codable

    @Suite("ChatMessage Codable")
    struct ChatMessageCodableTests {

        private func makeEncoder() -> JSONEncoder {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            return enc
        }

        private func makeDecoder() -> JSONDecoder {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            return dec
        }

        @Test("User message round-trips through JSON")
        func userMessageRoundTrip() throws {
            let msg = ChatMessage.user("Hello world")
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.id == msg.id)
            #expect(decoded.role == .user)
            #expect(decoded.content == "Hello world")
            #expect(!decoded.isStreaming)
            #expect(decoded.thinkingWordCount == 0)
        }

        @Test("Assistant message with content round-trips")
        func assistantContentRoundTrip() throws {
            let msg = ChatMessage.assistant("Here is the answer")
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.role == .assistant)
            #expect(decoded.content == "Here is the answer")
            #expect(!decoded.isStreaming)
        }

        @Test("Message with benchmarkInfo round-trips")
        func benchmarkInfoRoundTrip() throws {
            var msg = ChatMessage.assistant("Response")
            msg.benchmarkInfo = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 33.7,
                timeToFirstToken: 0.45,
                tokenCount: 150
            )
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.benchmarkInfo != nil)
            #expect(decoded.benchmarkInfo?.tokenCount == 150)
            #expect(decoded.benchmarkInfo?.decodeTokensPerSecond == 33.7)
        }

        @Test("Message with attachments encodes metadata only")
        func attachmentsEncodeMetadata() throws {
            let msg = ChatMessage.user("Check this", imageData: Data(repeating: 0xFF, count: 500))
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.attachments.count == 1)
            #expect(decoded.attachments.first?.isImage == true)
        }

        @Test("Message with thinkingContent round-trips")
        func thinkingContentRoundTrip() throws {
            var msg = ChatMessage.assistant("Answer")
            msg.thinkingContent = "Step 1: analyze the question"
            msg.thinkingWordCount = 5
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.thinkingContent == "Step 1: analyze the question")
            #expect(decoded.thinkingWordCount == 5)
        }

        @Test("Message with nil optional fields round-trips")
        func nilOptionalFieldsRoundTrip() throws {
            let msg = ChatMessage.user("Simple message")
            let data = try makeEncoder().encode(msg)
            let decoded = try makeDecoder().decode(ChatMessage.self, from: data)

            #expect(decoded.thinkingContent == nil)
            #expect(decoded.benchmarkInfo == nil)
            #expect(decoded.toolCalls.isEmpty)
            #expect(decoded.specialResults.isEmpty)
        }
    }

    // MARK: - ConversationState Computed Properties

    @Suite("ConversationState Computed Properties")
    struct ConversationStatePropertyTests {

        @Test("isEmpty is true for empty state, false after append")
        func isEmptyProperty() {
            var state = ConversationState()
            #expect(state.isEmpty)

            state.append(.user("Hello"))
            #expect(!state.isEmpty)
        }

        @Test("count reflects number of messages")
        func countProperty() {
            var state = ConversationState()
            #expect(state.count == 0)

            state.append(.user("One"))
            #expect(state.count == 1)

            state.append(.assistant("Two"))
            #expect(state.count == 2)

            state.append(.system("Three"))
            #expect(state.count == 3)
        }

        @Test("lastMessage returns the most recently appended message")
        func lastMessageProperty() {
            var state = ConversationState()
            #expect(state.lastMessage == nil)

            state.append(.user("First"))
            #expect(state.lastMessage?.content == "First")

            state.append(.assistant("Second"))
            #expect(state.lastMessage?.content == "Second")
        }

        @Test("isAssistantStreaming is false when last message is not assistant")
        func notStreamingWhenNotAssistant() {
            var state = ConversationState()
            state.append(.user("Hello"))
            #expect(!state.isAssistantStreaming)
        }

        @Test("isAssistantStreaming is true when last message is streaming assistant")
        func streamingAssistant() {
            var state = ConversationState()
            state.append(.assistant())  // streaming by default
            #expect(state.isAssistantStreaming)
        }

        @Test("isAssistantStreaming is false when assistant stops streaming")
        func stoppedStreaming() {
            var state = ConversationState()
            state.append(.assistant())
            state.updateLastAssistantMessage(isStreaming: false)
            #expect(!state.isAssistantStreaming)
        }

        @Test("clear removes all messages and resets computed properties")
        func clearResetsAll() {
            var state = ConversationState()
            state.append(.user("A"))
            state.append(.assistant("B"))
            state.clear()

            #expect(state.isEmpty)
            #expect(state.count == 0)
            #expect(state.lastMessage == nil)
            #expect(!state.isAssistantStreaming)
        }

        @Test("updateLastAssistantMessage is no-op when last message is not assistant")
        func updateNoOpWhenNotAssistant() {
            var state = ConversationState()
            state.append(.user("Hello"))

            // Should not crash or change anything
            state.updateLastAssistantMessage(content: "Should not apply")
            #expect(state.lastMessage?.content == "Hello")
            #expect(state.lastMessage?.role == .user)
        }

        @Test("updateLastAssistantMessage updates benchmarkInfo")
        func updateBenchmark() {
            var state = ConversationState()
            state.append(.assistant())

            let benchmark = ChatMessage.BenchmarkSnapshot(
                decodeTokensPerSecond: 25.0,
                timeToFirstToken: 0.3,
                tokenCount: 80
            )
            state.updateLastAssistantMessage(benchmarkInfo: benchmark)

            #expect(state.lastMessage?.benchmarkInfo?.tokenCount == 80)
            #expect(state.lastMessage?.benchmarkInfo?.decodeTokensPerSecond == 25.0)
        }
    }
}

// MARK: - ToolCallEvent Property Tests

@Suite("ToolCallEvent Properties")
struct ToolCallEventPropertySwiftTests {

    @Test("Init assigns all properties correctly")
    func initProperties() {
        let now = Date()
        let event = ToolCallEvent(
            toolName: "calculate",
            arguments: "{\"expression\": \"2+2\"}",
            result: "{\"value\": 4}",
            durationMs: 12.5,
            timestamp: now,
            succeeded: true
        )

        #expect(event.toolName == "calculate")
        #expect(event.arguments == "{\"expression\": \"2+2\"}")
        #expect(event.result == "{\"value\": 4}")
        #expect(event.durationMs == 12.5)
        #expect(event.timestamp == now)
        #expect(event.succeeded == true)
        #expect(event.id != UUID()) // has a unique ID
    }

    @Test("Failed tool call stores succeeded as false")
    func failedToolCall() {
        let event = ToolCallEvent(
            toolName: "fetch",
            arguments: "{}",
            result: "Error: timeout",
            durationMs: 5000.0,
            timestamp: Date(),
            succeeded: false
        )
        #expect(!event.succeeded)
        #expect(event.result == "Error: timeout")
    }

    @Test("Each init creates a unique UUID")
    func uniqueIds() {
        let a = ToolCallEvent(toolName: "t", arguments: "{}", result: "{}", durationMs: 0, timestamp: Date(), succeeded: true)
        let b = ToolCallEvent(toolName: "t", arguments: "{}", result: "{}", durationMs: 0, timestamp: Date(), succeeded: true)
        #expect(a.id != b.id)
    }

    @Test("Codable round-trip preserves all values")
    func codableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let now = Date()
        let event = ToolCallEvent(
            toolName: "get_device_info",
            arguments: "{\"key\": \"battery\"}",
            result: "{\"level\": 85}",
            durationMs: 3.14,
            timestamp: now,
            succeeded: true
        )

        let data = try encoder.encode(event)
        let decoded = try decoder.decode(ToolCallEvent.self, from: data)

        #expect(decoded.id == event.id)
        #expect(decoded.toolName == event.toolName)
        #expect(decoded.arguments == event.arguments)
        #expect(decoded.result == event.result)
        #expect(decoded.durationMs == event.durationMs)
        #expect(decoded.succeeded == event.succeeded)
    }

    @Test("ToolCallEvent with special results can be parsed in ConversationState")
    func toolCallWithSpecialResult() {
        let specialJSON = """
        {"type":"wikipedia","query":"Swift","title":"Swift","extract":"A language","url":"https://example.com","thumbnail_url":null,"latitude":null,"longitude":null,"subtitle":null}
        """

        var state = ConversationState()
        state.append(.user("Tell me about Swift"))
        state.append(.assistant())

        let event = ToolCallEvent(
            toolName: "wikipedia",
            arguments: "{\"query\": \"Swift\"}",
            result: specialJSON,
            durationMs: 50.0,
            timestamp: Date(),
            succeeded: true
        )

        state.updateLastAssistantMessage(toolCalls: [event])

        #expect(state.lastMessage?.toolCalls.count == 1)
        #expect(state.lastMessage?.specialResults.count == 1)

        let parsed = state.lastMessage?.specialResults.values.first
        #expect(parsed?.type == "wikipedia")
        #expect(parsed?.title == "Swift")
    }
}
