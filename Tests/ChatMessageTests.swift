import XCTest

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Chat Message Tests

final class ChatMessageTests: XCTestCase {

    // MARK: - ChatMessage Factory Methods

    func testUserMessageCreation() {
        let msg = ChatMessage.user("Hello")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content, "Hello")
        XCTAssertFalse(msg.isStreaming)
        XCTAssertTrue(msg.attachments.isEmpty)
    }

    func testUserMessageWithAttachments() {
        let msg = ChatMessage.user("See this", imageData: Data([1, 2, 3]))
        XCTAssertEqual(msg.attachments.count, 1)
        XCTAssertTrue(msg.attachments.first?.isImage ?? false)
    }

    func testAssistantMessageCreation() {
        let msg = ChatMessage.assistant()
        XCTAssertEqual(msg.role, .assistant)
        XCTAssertEqual(msg.content, "")
        XCTAssertTrue(msg.isStreaming)
    }

    func testSystemMessageCreation() {
        let msg = ChatMessage.system("You are helpful")
        XCTAssertEqual(msg.role, .system)
        XCTAssertEqual(msg.content, "You are helpful")
        XCTAssertFalse(msg.isStreaming)
    }

    // MARK: - ConversationState Tests

    func testConversationStateAppend() {
        var state = ConversationState()
        XCTAssertTrue(state.isEmpty)
        state.append(.user("Hello"))
        XCTAssertEqual(state.count, 1)
        XCTAssertFalse(state.isEmpty)
    }

    func testConversationStateUpdateLastAssistant() {
        var state = ConversationState()
        state.append(.user("Hi"))
        state.append(.assistant())

        state.updateLastAssistantMessage(content: "Hello there!")
        XCTAssertEqual(state.lastMessage?.content, "Hello there!")

        state.updateLastAssistantMessage(isStreaming: false)
        XCTAssertFalse(state.lastMessage?.isStreaming ?? true)
    }

    func testConversationStateClear() {
        var state = ConversationState()
        state.append(.user("Hello"))
        state.append(.assistant())
        XCTAssertEqual(state.count, 2)
        state.clear()
        XCTAssertTrue(state.isEmpty)
    }

    func testIsAssistantStreaming() {
        var state = ConversationState()
        XCTAssertFalse(state.isAssistantStreaming)

        state.append(.user("Hi"))
        XCTAssertFalse(state.isAssistantStreaming)

        state.append(.assistant())
        XCTAssertTrue(state.isAssistantStreaming)

        state.updateLastAssistantMessage(isStreaming: false)
        XCTAssertFalse(state.isAssistantStreaming)
    }
}
