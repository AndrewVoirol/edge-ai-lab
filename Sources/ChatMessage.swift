import Foundation
import LiteRTLM

// MARK: - Chat Message

/// Represents a single message in a multi-turn conversation.
/// Used to build the chat bubble UI and persist conversation state.
struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var thinkingContent: String?
    var toolCalls: [ToolCallEvent]
    var attachments: [Attachment]
    let timestamp: Date
    var benchmarkInfo: BenchmarkSnapshot?
    var isStreaming: Bool
    
    /// The role of the message sender.
    enum Role: String, Sendable, Codable {
        case user
        case assistant
        case system
        case toolResult
    }
    
    /// A multimodal attachment on a message.
    enum Attachment: Sendable {
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
    }
    
    /// Lightweight snapshot of benchmark data for a single message.
    struct BenchmarkSnapshot: Sendable {
        let decodeTokensPerSecond: Double
        let timeToFirstToken: Double
        let tokenCount: Int
        
        init(from info: BenchmarkInfo) {
            self.decodeTokensPerSecond = info.lastDecodeTokensPerSecond
            self.timeToFirstToken = info.timeToFirstTokenInSecond
            self.tokenCount = info.lastDecodeTokenCount
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
            isStreaming: false
        )
    }
    
    /// Create an assistant message (initially empty, filled via streaming).
    static func assistant() -> ChatMessage {
        ChatMessage(
            id: UUID(),
            role: .assistant,
            content: "",
            thinkingContent: nil,
            toolCalls: [],
            attachments: [],
            timestamp: Date(),
            benchmarkInfo: nil,
            isStreaming: true
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
            isStreaming: false
        )
    }
}

// MARK: - Conversation State

/// Manages the ordered list of messages in a conversation.
struct ConversationState {
    private(set) var messages: [ChatMessage] = []
    
    /// Add a new message to the conversation.
    mutating func append(_ message: ChatMessage) {
        messages.append(message)
    }
    
    /// Update the last assistant message (used during streaming).
    mutating func updateLastAssistantMessage(
        content: String? = nil,
        thinkingContent: String? = nil,
        toolCalls: [ToolCallEvent]? = nil,
        isStreaming: Bool? = nil,
        benchmarkInfo: ChatMessage.BenchmarkSnapshot? = nil
    ) {
        guard let lastIndex = messages.indices.last,
              messages[lastIndex].role == .assistant else { return }
        if let content = content {
            messages[lastIndex].content = content
        }
        if let thinking = thinkingContent {
            messages[lastIndex].thinkingContent = thinking
        }
        if let tools = toolCalls {
            messages[lastIndex].toolCalls = tools
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
