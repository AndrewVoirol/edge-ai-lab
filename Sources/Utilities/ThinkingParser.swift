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

// MARK: - Thinking Parser

/// Streaming-aware parser that separates `<think>...</think>` reasoning blocks
/// from regular response content in Gemma 4 model output.
///
/// Thinking mode allows the model to "reason" internally before producing the final answer.
/// This parser handles:
/// - Complete think blocks within a single chunk
/// - Think blocks split across multiple streaming chunks
/// - Multiple think blocks in a single response
/// - Partial/incomplete tags at chunk boundaries
///
/// Usage:
/// ```swift
/// var parser = ThinkingParser()
/// for chunk in streamedChunks {
///     let segments = parser.feed(chunk)
///     for segment in segments {
///         switch segment {
///         case .thinking(let text): thinkingContent += text
///         case .response(let text): responseContent += text
///         }
///     }
/// }
/// // Handle any remaining buffered content
/// let final = parser.finalize()
/// ```
struct ThinkingParser {

  /// A parsed segment from the model's output.
  enum Segment: Equatable {
    /// Content inside `<think>...</think>` — the model's reasoning scratchpad.
    case thinking(String)
    /// Regular response content — the model's final answer.
    case response(String)

    var text: String {
      switch self {
      case .thinking(let t), .response(let t): return t
      }
    }

    var isThinking: Bool {
      if case .thinking = self { return true }
      return false
    }
  }

  // MARK: - Parser State

  /// Tracks whether the parser is currently inside or outside a think block.
  private enum State {
    /// Outside any think block — content is regular response text.
    case normal
    /// Inside a `<think>...</think>` block — content is reasoning text.
    case thinking
  }

  private var state: State = .normal

  /// Working buffer that accumulates input until complete tags can be identified.
  /// Partial tags at chunk boundaries are retained here between `feed()` calls.
  private var buffer: String = ""

  // MARK: - Tag Definitions

  /// Supported opening tag variants for think blocks.
  /// - `<think>` / `<|think|>`: Standard tags used by Gemma models via LiteRT.
  /// - `<|channel>thought`: Gemma 4 MLX channel-based thinking marker.
  ///   The model emits `<|channel>thought\n{text}\n<channel|>` for thinking content.
  private static let openTags = ["<think>", "<|think|>", "<|channel>thought\n", "<|channel>thought"]

  /// Closing tag variants for think blocks.
  /// - `</think>`: Standard close tag for `<think>` / `<|think|>` open tags.
  /// - `<channel|>`: Gemma 4 MLX channel-based thinking close marker.
  private static let closeTags = ["</think>", "\n<channel|>", "<channel|>"]

  /// The maximum length among all supported tags. Used to determine how much
  /// trailing content to retain in the buffer when a partial tag might be present.
  private static let maxTagLength: Int = {
    let allTags = openTags + closeTags
    return allTags.map(\.count).max() ?? 0
  }()

  // MARK: - Public API

  /// Feed a new streaming chunk into the parser.
  ///
  /// The chunk is appended to an internal buffer. The parser scans for complete
  /// open/close tags and emits parsed segments. Any trailing content that could
  /// be a partial tag is retained in the buffer for the next call.
  ///
  /// - Parameter chunk: The next piece of streamed text from the model.
  /// - Returns: An array of segments extracted from the accumulated input.
  ///   May be empty if the chunk only contained a partial tag.
  mutating func feed(_ chunk: String) -> [Segment] {
    guard !chunk.isEmpty else { return [] }

    buffer += chunk
    return drainBuffer(isFinal: false)
  }

  /// Finalize parsing after the stream ends.
  ///
  /// Flushes any remaining buffered content. Partial/incomplete tags are treated
  /// as literal text since no more input will arrive to complete them.
  ///
  /// - Returns: Any remaining buffered content as segments.
  mutating func finalize() -> [Segment] {
    return drainBuffer(isFinal: true)
  }

  /// Reset the parser to its initial state, clearing all buffers.
  mutating func reset() {
    state = .normal
    buffer = ""
  }

  // MARK: - Core Parsing Logic

  /// Scans the buffer for complete tags and emits segments.
  ///
  /// - Parameter isFinal: When `true`, all remaining buffer content is flushed
  ///   as-is (partial tags become literal text). When `false`, a trailing window
  ///   of characters is retained in case it forms part of a tag split across chunks.
  /// - Returns: Array of parsed segments.
  private mutating func drainBuffer(isFinal: Bool) -> [Segment] {
    var segments: [Segment] = []

    while !buffer.isEmpty {
      // Determine which tags to search for based on current state.
      let tagsToFind: [String]
      switch state {
      case .normal:
        tagsToFind = Self.openTags
      case .thinking:
        tagsToFind = Self.closeTags
      }

      // Find the earliest occurrence of any relevant tag in the buffer.
      let match = findEarliestTag(in: buffer, from: tagsToFind)

      if let (tagRange, _) = match {
        // A complete tag was found. Emit everything before it as the current segment type.
        let beforeTag = String(buffer[buffer.startIndex..<tagRange.lowerBound])
        if !beforeTag.isEmpty {
          segments.append(makeSegment(beforeTag))
        }

        // Advance past the tag and switch state.
        buffer = String(buffer[tagRange.upperBound...])
        switch state {
        case .normal:
          state = .thinking
        case .thinking:
          state = .normal
        }
        // Continue scanning the remaining buffer for more tags.
      } else {
        // No complete tag found in the buffer.
        if isFinal {
          // Stream is done — flush everything as literal text.
          if !buffer.isEmpty {
            segments.append(makeSegment(buffer))
            buffer = ""
          }
        } else {
          // Retain a trailing window that could be a partial tag.
          // Any `<` near the end of the buffer might be the start of a tag
          // that will be completed by the next chunk.
          let safeEmitEnd = findSafeEmitBoundary(in: buffer)
          if safeEmitEnd > buffer.startIndex {
            let emittable = String(buffer[buffer.startIndex..<safeEmitEnd])
            segments.append(makeSegment(emittable))
            buffer = String(buffer[safeEmitEnd...])
          }
          // Stop scanning — we need more input.
          break
        }
      }
    }

    return segments
  }

  /// Creates a segment of the appropriate type based on current parser state.
  private func makeSegment(_ text: String) -> Segment {
    switch state {
    case .normal: return .response(text)
    case .thinking: return .thinking(text)
    }
  }

  /// Finds the earliest occurrence of any tag from the given list within the buffer.
  ///
  /// - Parameters:
  ///   - buffer: The string to search.
  ///   - tags: The set of tag strings to look for.
  /// - Returns: A tuple of the matched tag's range and the tag string, or `nil` if not found.
  private func findEarliestTag(
    in buffer: String, from tags: [String]
  ) -> (Range<String.Index>, String)? {
    var earliest: (Range<String.Index>, String)?

    for tag in tags {
      if let range = buffer.range(of: tag) {
        if let current = earliest {
          if range.lowerBound < current.0.lowerBound {
            earliest = (range, tag)
          }
        } else {
          earliest = (range, tag)
        }
      }
    }

    return earliest
  }

  /// Determines the safe boundary up to which buffer content can be emitted
  /// without risking splitting a tag across chunks.
  ///
  /// Scans backwards from the end of the buffer looking for a `<` character.
  /// If a `<` is found within `maxTagLength` characters of the end, everything
  /// before that `<` is safe to emit — the rest is retained as a potential
  /// partial tag. If no `<` is found in that window, the entire buffer is safe.
  ///
  /// - Parameter buffer: The current buffer contents.
  /// - Returns: The index up to which content can be safely emitted.
  private func findSafeEmitBoundary(in buffer: String) -> String.Index {
    // Look for a `<` in the trailing window that could start a partial tag.
    // The window size is maxTagLength - 1 because a complete tag would have
    // already been matched by findEarliestTag.
    let windowSize = Self.maxTagLength - 1
    guard buffer.count > windowSize else {
      // The entire buffer is shorter than a tag — retain all of it.
      return buffer.startIndex
    }

    let windowStart = buffer.index(buffer.endIndex, offsetBy: -windowSize)

    // Search for `<` within the trailing window.
    if let angleBracket = buffer[windowStart...].firstIndex(of: "<") {
      return angleBracket
    }

    // No potential tag start found — the entire buffer is safe to emit.
    return buffer.endIndex
  }
}

// MARK: - Convenience Extensions

extension ThinkingParser {

  /// Parse a complete (non-streaming) response string into thinking and response components.
  ///
  /// This is a convenience method for when the full model output is already available
  /// and streaming isn't needed.
  ///
  /// - Parameter text: The complete model output text.
  /// - Returns: A tuple separating the thinking (reasoning) content from the response content.
  static func parse(_ text: String) -> (thinking: String, response: String) {
    var parser = ThinkingParser()
    let segments = parser.feed(text) + parser.finalize()
    var thinking = ""
    var response = ""
    for segment in segments {
      switch segment {
      case .thinking(let t): thinking += t
      case .response(let t): response += t
      }
    }
    return (thinking: thinking, response: response)
  }
}
