import XCTest

#if os(iOS)
@testable import GemmaEdgeGallery_iOS
#elseif os(macOS)
@testable import GemmaEdgeGallery_macOS
#endif

// MARK: - Thinking Parser Tests

final class ThinkingParserTests: XCTestCase {

    // MARK: - Basic Parsing (Static API)

    func testNoThinkTags() {
        let (thinking, response) = ThinkingParser.parse("Just a normal response")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "Just a normal response")
    }

    func testSimpleThinkBlock() {
        let (thinking, response) = ThinkingParser.parse("<think>Let me reason</think>The answer is 42")
        XCTAssertEqual(thinking, "Let me reason")
        XCTAssertEqual(response, "The answer is 42")
    }

    func testAlternateThinkTag() {
        let (thinking, response) = ThinkingParser.parse("<|think|>Reasoning here</think>Answer")
        XCTAssertEqual(thinking, "Reasoning here")
        XCTAssertEqual(response, "Answer")
    }

    func testThinkAtStart() {
        let (thinking, response) = ThinkingParser.parse("<think>First think</think>Response")
        XCTAssertEqual(thinking, "First think")
        XCTAssertEqual(response, "Response")
    }

    func testMultipleThinkBlocks() {
        let text = "<think>Block1</think>Middle<think>Block2</think>End"
        let (thinking, response) = ThinkingParser.parse(text)
        XCTAssertEqual(thinking, "Block1Block2")
        XCTAssertEqual(response, "MiddleEnd")
    }

    func testEmptyInput() {
        let (thinking, response) = ThinkingParser.parse("")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "")
    }

    func testOnlyThinking() {
        let (thinking, response) = ThinkingParser.parse("<think>Just thinking</think>")
        XCTAssertEqual(thinking, "Just thinking")
        XCTAssertEqual(response, "")
    }

    // MARK: - Streaming Tests

    func testStreamingSplitTag() {
        var parser = ThinkingParser()
        // Tag split across chunks: "<thi" + "nk>"
        let s1 = parser.feed("Hello <thi")
        let s2 = parser.feed("nk>reasoning")
        let s3 = parser.feed("</think>done")
        let s4 = parser.finalize()

        let allSegments = s1 + s2 + s3 + s4
        let thinking = allSegments.filter { $0.isThinking }.map { $0.text }.joined()
        let response = allSegments.filter { !$0.isThinking }.map { $0.text }.joined()

        XCTAssertEqual(thinking, "reasoning")
        XCTAssertEqual(response, "Hello done")
    }

    func testStreamingMultipleChunks() {
        var parser = ThinkingParser()
        let chunks = ["<think>", "step ", "1", "</think>", "answer"]
        var thinking = ""
        var response = ""
        for chunk in chunks {
            for segment in parser.feed(chunk) {
                switch segment {
                case .thinking(let t): thinking += t
                case .response(let t): response += t
                }
            }
        }
        for segment in parser.finalize() {
            switch segment {
            case .thinking(let t): thinking += t
            case .response(let t): response += t
            }
        }
        XCTAssertEqual(thinking, "step 1")
        XCTAssertEqual(response, "answer")
    }

    // Test that non-think angle brackets pass through as response text
    func testHtmlTagsNotConfused() {
        let (thinking, response) = ThinkingParser.parse("Use <div> and <span> tags")
        XCTAssertEqual(thinking, "")
        XCTAssertEqual(response, "Use <div> and <span> tags")
    }

    func testResetParser() {
        var parser = ThinkingParser()
        _ = parser.feed("<think>partial")
        parser.reset()
        let segments = parser.feed("clean start") + parser.finalize()
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.text, "clean start")
        XCTAssertFalse(segments.first?.isThinking ?? true)
    }
}
