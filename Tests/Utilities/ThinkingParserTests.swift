// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing
import Foundation

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - Streaming API Tests

@Suite("ThinkingParser – Streaming")
struct ThinkingParserStreamingTests {

    @Test("Complete think block yields thinking + response segments")
    func completeThinkBlock() {
        var parser = ThinkingParser()
        let segments = parser.feed("<think>reasoning</think>response") + parser.finalize()
        #expect(segments == [.thinking("reasoning"), .response("response")])
    }

    @Test("Plain text without tags yields response only")
    func responseOnly() {
        var parser = ThinkingParser()
        let segments = parser.feed("plain text") + parser.finalize()
        #expect(segments.count == 1)
        let combined = segments.map(\.text).joined()
        #expect(combined == "plain text")
        #expect(segments.allSatisfy { !$0.isThinking })
    }

    @Test("Think block with no trailing response yields thinking only")
    func thinkBlockOnly() {
        var parser = ThinkingParser()
        let segments = parser.feed("<think>reasoning</think>") + parser.finalize()
        #expect(segments == [.thinking("reasoning")])
    }

    @Test("Empty think block yields no thinking content")
    func emptyThinkBlock() {
        var parser = ThinkingParser()
        let segments = parser.feed("<think></think>") + parser.finalize()
        // Empty think block — no thinking segment emitted (empty string not appended)
        let thinkingText = segments.filter(\.isThinking).map(\.text).joined()
        #expect(thinkingText.isEmpty)
    }

    @Test("Multiple think blocks produce correct segment sequence")
    func multipleThinkBlocks() {
        var parser = ThinkingParser()
        let segments = parser.feed("<think>a</think>middle<think>b</think>end") + parser.finalize()
        let thinkingTexts = segments.filter(\.isThinking).map(\.text)
        let responseTexts = segments.filter { !$0.isThinking }.map(\.text)
        #expect(thinkingTexts == ["a", "b"])
        #expect(responseTexts.joined() == "middleend")
        #expect(segments.count == 4)
    }

    @Test("Pipe-delimited open tag is recognized")
    func pipeDelimitedOpenTag() {
        var parser = ThinkingParser()
        let segments = parser.feed("<|think|>reasoning</think>response") + parser.finalize()
        #expect(segments == [.thinking("reasoning"), .response("response")])
    }

    @Test("MLX channel tags parse thinking correctly")
    func mlxChannelTags() {
        var parser = ThinkingParser()
        let input = "<|channel>thought\nreasoning\n<channel|>response"
        let segments = parser.feed(input) + parser.finalize()
        let thinking = segments.filter(\.isThinking).map(\.text).joined()
        let response = segments.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "reasoning")
        #expect(response == "response")
    }

    @Test("MLX channel tag without trailing newline still opens thinking")
    func mlxChannelTagNoNewline() {
        var parser = ThinkingParser()
        // "<|channel>thought" (without \n) is also an open tag per openTags definition
        let input = "<|channel>thoughtsome reasoning<channel|>answer"
        let segments = parser.feed(input) + parser.finalize()
        let thinking = segments.filter(\.isThinking).map(\.text).joined()
        let response = segments.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "some reasoning")
        #expect(response == "answer")
    }

    @Test("Streaming: tag split across two chunks at open tag")
    func streamingSplitOpenTag() {
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        all += parser.feed("<thi")
        all += parser.feed("nk>content</think>response")
        all += parser.finalize()
        let thinking = all.filter(\.isThinking).map(\.text).joined()
        let response = all.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "content")
        #expect(response == "response")
    }

    @Test("Streaming: tag split across two chunks at close tag")
    func streamingSplitCloseTag() {
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        all += parser.feed("<think>content</thi")
        all += parser.feed("nk>response")
        all += parser.finalize()
        let thinking = all.filter(\.isThinking).map(\.text).joined()
        let response = all.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "content")
        #expect(response == "response")
    }

    @Test("Streaming: character-by-character feed produces correct result")
    func streamingCharByChar() {
        let input = "<think>hi</think>bye"
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        for char in input {
            all += parser.feed(String(char))
        }
        all += parser.finalize()
        let thinking = all.filter(\.isThinking).map(\.text).joined()
        let response = all.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "hi")
        #expect(response == "bye")
    }

    @Test("Finalize with partial tag emits literal text")
    func finalizePartialTag() {
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        all += parser.feed("<thin")
        all += parser.finalize()
        let combined = all.map(\.text).joined()
        #expect(combined == "<thin")
        #expect(all.allSatisfy { !$0.isThinking })
    }

    @Test("Finalize with unclosed think block emits as thinking")
    func finalizeUnclosedThinkBlock() {
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        all += parser.feed("<think>content")
        all += parser.finalize()
        let thinking = all.filter(\.isThinking).map(\.text).joined()
        #expect(thinking == "content")
    }

    @Test("Empty feed returns empty array")
    func emptyFeed() {
        var parser = ThinkingParser()
        let segments = parser.feed("")
        #expect(segments.isEmpty)
    }

    @Test("Reset clears state and buffer")
    func resetClearsState() {
        var parser = ThinkingParser()
        _ = parser.feed("<think>")
        parser.reset()
        let segments = parser.feed("text") + parser.finalize()
        let combined = segments.map(\.text).joined()
        #expect(combined == "text")
        // After reset, parser is in .normal state — all output should be response
        #expect(segments.allSatisfy { !$0.isThinking })
    }

    @Test("Angle brackets that don't form tags are preserved as text")
    func angleBracketsNotTags() {
        var parser = ThinkingParser()
        let input = "x < y and z > w"
        let segments = parser.feed(input) + parser.finalize()
        let combined = segments.map(\.text).joined()
        #expect(combined == input)
        #expect(segments.allSatisfy { !$0.isThinking })
    }

    @Test("Large content in think block is handled correctly")
    func largeContent() {
        let longText = String(repeating: "abcdefghij", count: 200)  // 2000 chars
        var parser = ThinkingParser()
        let input = "<think>\(longText)</think>done"
        let segments = parser.feed(input) + parser.finalize()
        let thinking = segments.filter(\.isThinking).map(\.text).joined()
        let response = segments.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == longText)
        #expect(response == "done")
    }

    @Test("Multiple streaming chunks accumulate correctly")
    func multipleStreamingChunks() {
        var parser = ThinkingParser()
        var all: [ThinkingParser.Segment] = []
        all += parser.feed("<think>")
        all += parser.feed("reasoning content")
        all += parser.feed("</think>")
        all += parser.feed("final answer")
        all += parser.finalize()
        let thinking = all.filter(\.isThinking).map(\.text).joined()
        let response = all.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "reasoning content")
        #expect(response == "final answer")
    }

    @Test("Mixed tags: pipe-delimited open with standard close")
    func mixedTags() {
        var parser = ThinkingParser()
        let segments = parser.feed("<|think|>reasoning</think>answer") + parser.finalize()
        let thinking = segments.filter(\.isThinking).map(\.text).joined()
        let response = segments.filter { !$0.isThinking }.map(\.text).joined()
        #expect(thinking == "reasoning")
        #expect(response == "answer")
    }
}

// MARK: - Convenience API Tests

@Suite("ThinkingParser – Convenience")
struct ThinkingParserConvenienceTests {

    @Test("parse() splits thinking and response")
    func parseConvenience() {
        let result = ThinkingParser.parse("<think>r</think>a")
        #expect(result.thinking == "r")
        #expect(result.response == "a")
    }

    @Test("parse() with no thinking returns empty thinking string")
    func parseNoThinking() {
        let result = ThinkingParser.parse("just text")
        #expect(result.thinking == "")
        #expect(result.response == "just text")
    }
}

// MARK: - Segment Enum Tests

@Suite("ThinkingParser.Segment")
struct ThinkingParserSegmentTests {

    @Test("Equatable: same case and value are equal")
    func equatableSameCase() {
        #expect(ThinkingParser.Segment.thinking("a") == ThinkingParser.Segment.thinking("a"))
        #expect(ThinkingParser.Segment.response("b") == ThinkingParser.Segment.response("b"))
    }

    @Test("Equatable: different cases are not equal")
    func equatableDifferentCase() {
        #expect(ThinkingParser.Segment.thinking("a") != ThinkingParser.Segment.response("a"))
    }

    @Test("text property returns associated string")
    func textProperty() {
        #expect(ThinkingParser.Segment.thinking("abc").text == "abc")
        #expect(ThinkingParser.Segment.response("xyz").text == "xyz")
    }

    @Test("isThinking returns true for thinking, false for response")
    func isThinkingProperty() {
        #expect(ThinkingParser.Segment.thinking("x").isThinking == true)
        #expect(ThinkingParser.Segment.response("x").isThinking == false)
    }
}
