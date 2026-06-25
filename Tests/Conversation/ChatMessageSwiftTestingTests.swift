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
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Chat Message Swift Testing Tests

@Suite("ChatMessage Factory & ConversationState")
struct ChatMessageSwiftTestingTests {

    // MARK: - ChatMessage Factory Methods

    @Test("User message has correct role, content, and defaults")
    func userMessageCreation() {
        let msg = ChatMessage.user("Hello")
        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
        #expect(!msg.isStreaming)
        #expect(msg.attachments.isEmpty)
    }

    @Test("User message with image data has one image attachment")
    func userMessageWithAttachments() {
        let msg = ChatMessage.user("See this", imageData: Data([1, 2, 3]))
        #expect(msg.attachments.count == 1)
        #expect(msg.attachments.first?.isImage ?? false)
    }

    @Test("Assistant message starts streaming with empty content")
    func assistantMessageCreation() {
        let msg = ChatMessage.assistant()
        #expect(msg.role == .assistant)
        #expect(msg.content == "")
        #expect(msg.isStreaming)
    }

    @Test("System message has correct role and content")
    func systemMessageCreation() {
        let msg = ChatMessage.system("You are helpful")
        #expect(msg.role == .system)
        #expect(msg.content == "You are helpful")
        #expect(!msg.isStreaming)
    }

    // MARK: - ConversationState Tests

    @Test("Appending messages updates count and isEmpty")
    func conversationStateAppend() {
        var state = ConversationState()
        #expect(state.isEmpty)
        state.append(.user("Hello"))
        #expect(state.count == 1)
        #expect(!state.isEmpty)
    }

    @Test("Updating last assistant message changes content and streaming flag")
    func conversationStateUpdateLastAssistant() {
        var state = ConversationState()
        state.append(.user("Hi"))
        state.append(.assistant())

        state.updateLastAssistantMessage(content: "Hello there!")
        #expect(state.lastMessage?.content == "Hello there!")

        state.updateLastAssistantMessage(isStreaming: false)
        #expect(!(state.lastMessage?.isStreaming ?? true))
    }

    @Test("Clearing conversation removes all messages")
    func conversationStateClear() {
        var state = ConversationState()
        state.append(.user("Hello"))
        state.append(.assistant())
        #expect(state.count == 2)
        state.clear()
        #expect(state.isEmpty)
    }

    // MARK: - Streaming State Transitions (Parameterized)

    /// Represents a step in a streaming state test scenario.
    struct StreamingStep: CustomStringConvertible, Sendable {
        let label: String
        let action: @Sendable (inout ConversationState) -> Void
        let expectedStreaming: Bool

        var description: String { label }
    }

    @Test(
        "isAssistantStreaming transitions correctly",
        arguments: [
            ("Empty state", false),
            ("After user message", false),
            ("After assistant starts", true),
            ("After streaming ends", false),
        ] as [(String, Bool)]
    )
    func isAssistantStreamingTransitions(label: String, expectedStreaming: Bool) {
        var state = ConversationState()

        // Build up state progressively based on label
        if label != "Empty state" {
            state.append(.user("Hi"))
        }
        if label == "After assistant starts" || label == "After streaming ends" {
            state.append(.assistant())
        }
        if label == "After streaming ends" {
            state.updateLastAssistantMessage(isStreaming: false)
        }

        #expect(state.isAssistantStreaming == expectedStreaming)
    }
}
