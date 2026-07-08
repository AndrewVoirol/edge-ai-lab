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

// MARK: - Chat Message

/// Represents a single message in a multi-turn conversation.
/// Used to build the chat bubble UI and persist conversation state.
struct ChatMessage: Identifiable, Sendable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var thinkingContent: String?
    var toolCalls: [ToolCallEvent]
    var attachments: [Attachment]
    let timestamp: Date
    var benchmarkInfo: BenchmarkSnapshot?
    /// Config snapshot capturing exactly what engine/settings produced this response.
    /// Only present on assistant messages created after Phase 2B.
    var inferenceConfig: InferenceConfigSnapshot?
    var isStreaming: Bool
    var thinkingWordCount: Int
    var specialResults: [UUID: SpecialResult]
    
    
    /// The role of the message sender.
    enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
        case toolResult
    }
    
    /// A multimodal attachment on a message.
    ///
    /// **Persistence**: When encoded to JSON, only metadata is stored (type + size).
    /// Binary data is NOT persisted to keep conversation files small.
    enum Attachment: Sendable, Codable {
        case image(Data)
        case audio(Data)
        
        var isImage: Bool {
            if case .image = self { return true }
            return false
        }
        
        var isAudio: Bool {
            if case .audio = self { return true }
            return false
        }
        
        // Custom Codable: encode as metadata only (type + size), decode as empty data
        private enum CodingKeys: String, CodingKey {
            case type, sizeBytes, note
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .image(let data):
                try container.encode("image", forKey: .type)
                try container.encode(data.count, forKey: .sizeBytes)
                try container.encode("[Image: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))]", forKey: .note)
            case .audio(let data):
                try container.encode("audio", forKey: .type)
                try container.encode(data.count, forKey: .sizeBytes)
                try container.encode("[Audio: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))]", forKey: .note)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            switch type {
            case "image": self = .image(Data())
            case "audio": self = .audio(Data())
            default: self = .image(Data())
            }
        }
    }
    
    /// Pre-decoded special results for agent skills (Wikipedia, Maps)
    struct SpecialResult: Codable, Sendable {
        let type: String
        let query: String?
        let title: String?
        let extract: String?
        let url: String?
        let thumbnail_url: String?
        let latitude: Double?
        let longitude: Double?
        let subtitle: String?
    }
    
    
    /// Lightweight snapshot of benchmark data for a single message.
    struct BenchmarkSnapshot: Sendable, Codable {
        let decodeTokensPerSecond: Double
        let timeToFirstToken: Double
        let tokenCount: Int
        
        init(from info: BenchmarkInfo) {
            self.decodeTokensPerSecond = info.lastDecodeTokensPerSecond
            self.timeToFirstToken = info.timeToFirstTokenInSecond
            self.tokenCount = info.lastDecodeTokenCount
        }

        /// Initialize from runtime-agnostic performance metrics.
        /// Used by the new `InferenceEngine` generation path.
        init(from metrics: EnginePerformanceMetrics) {
            self.decodeTokensPerSecond = metrics.tokensPerSecond
            self.timeToFirstToken = metrics.timeToFirstToken ?? 0
            self.tokenCount = metrics.tokenCount ?? 0
        }
        
        init(decodeTokensPerSecond: Double, timeToFirstToken: Double, tokenCount: Int) {
            self.decodeTokensPerSecond = decodeTokensPerSecond
            self.timeToFirstToken = timeToFirstToken
            self.tokenCount = tokenCount
        }
    }
    
    // MARK: - Convenience Initializers
    
    /// Create a user message.
    static func user(
        _ content: String,
        imageData: Data? = nil,
        audioData: Data? = nil
    ) -> ChatMessage {
        var attachments: [Attachment] = []
        if let img = imageData { attachments.append(.image(img)) }
        if let aud = audioData { attachments.append(.audio(aud)) }
        return ChatMessage(
            id: UUID(),
            role: .user,
            content: content,
            thinkingContent: nil,
            toolCalls: [],
            attachments: attachments,
            timestamp: Date(),
            benchmarkInfo: nil,
            isStreaming: false,
            thinkingWordCount: 0,
            specialResults: [:]
        )
    }
    
    /// Create an assistant message (initially empty, filled via streaming).
    /// - Parameter config: Optional config snapshot captured at inference start.
    static func assistant(config: InferenceConfigSnapshot? = nil) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "",
            thinkingContent: nil,
            toolCalls: [],
            attachments: [],
            timestamp: Date(),
            benchmarkInfo: nil,
            inferenceConfig: config,
            isStreaming: true,
            thinkingWordCount: 0,
            specialResults: [:]
        )
    }

    /// Create a completed assistant message with content (for persistence/testing).
    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: content,
            thinkingContent: nil,
            toolCalls: [],
            attachments: [],
            timestamp: Date(),
            benchmarkInfo: nil,
            isStreaming: false,
            thinkingWordCount: 0,
            specialResults: [:]
        )
    }
    
    /// Create a system message.
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .system,
            content: content,
            thinkingContent: nil,
            toolCalls: [],
            attachments: [],
            timestamp: Date(),
            benchmarkInfo: nil,
            isStreaming: false,
            thinkingWordCount: 0,
            specialResults: [:]
        )
    }
}

// MARK: - Conversation State

/// Manages the ordered list of messages in a conversation.
struct ConversationState: Codable {
    private(set) var messages: [ChatMessage] = []
    
    /// Add a new message to the conversation.
    mutating func append(_ message: ChatMessage) {
        messages.append(message)
    }
    
    /// Update the last assistant message (used during streaming).
    ///
    /// Searches backwards from the end of the messages array to find the
    /// most recent `.assistant` message. This is necessary because tool result
    /// messages (`.toolResult`) may be appended between assistant messages
    /// during tool calling — if we only checked the very last message, updates
    /// would be silently dropped when the last message is a tool result.
    mutating func updateLastAssistantMessage(
        content: String? = nil,
        thinkingContent: String? = nil,
        toolCalls: [ToolCallEvent]? = nil,
        isStreaming: Bool? = nil,
        benchmarkInfo: ChatMessage.BenchmarkSnapshot? = nil
    ) {
        guard let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        if let content = content {
            messages[lastIndex].content = content
        }
        if let thinking = thinkingContent {
            messages[lastIndex].thinkingContent = thinking
            messages[lastIndex].thinkingWordCount = thinking.split(separator: " ").count
        }
        if let tools = toolCalls {
            messages[lastIndex].toolCalls = tools
            for tool in tools {
                if messages[lastIndex].specialResults[tool.id] == nil,
                   let data = tool.result.data(using: .utf8),
                   let special = try? JSONDecoder().decode(ChatMessage.SpecialResult.self, from: data) {
                    messages[lastIndex].specialResults[tool.id] = special
                }
            }
        }
        if let streaming = isStreaming {
            messages[lastIndex].isStreaming = streaming
        }
        if let benchmark = benchmarkInfo {
            messages[lastIndex].benchmarkInfo = benchmark
        }
    }
    
    /// Clear all messages (new conversation).
    mutating func clear() {
        messages.removeAll()
    }
    
    /// Number of messages.
    var count: Int { messages.count }
    
    /// Whether the conversation is empty.
    var isEmpty: Bool { messages.isEmpty }
    
    /// The most recent message.
    var lastMessage: ChatMessage? { messages.last }
    
    /// Whether the assistant is currently streaming a response.
    var isAssistantStreaming: Bool {
        messages.last?.role == .assistant && (messages.last?.isStreaming ?? false)
    }
}
