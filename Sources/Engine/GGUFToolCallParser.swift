// Copyright 2026 Andrew Voirol. Apache-2.0
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

// MARK: - GGUFToolCallParser

/// Parses tool calls from GGUF model text output.
///
/// Gemma 4 models output tool calls in a specific format when function calling
/// is enabled. This parser extracts structured `AppToolCall` instances from
/// the raw text output.
///
/// ## Supported Formats
///
/// 1. **Standard JSON**: `{"function_call": {"name": "...", "arguments": {...}}}`
/// 2. **JSON Array**: `[{"function_call": {"name": "...", "arguments": {...}}}]`
/// 3. **Markdown code block**: ```json\n{"function_call": ...}\n```
///
/// ## Thread Safety
///
/// All methods are stateless and static — safe to call from any thread.
enum GGUFToolCallParser {

    // MARK: - Public API

    /// Attempt to parse tool calls from model output text.
    ///
    /// Scans the full generated text for tool call patterns. Returns an array
    /// of parsed tool calls, or an empty array if no tool calls are detected.
    ///
    /// - Parameter text: The complete generated text from the GGUF model.
    /// - Returns: Array of `AppToolCall` instances found in the text.
    static func parseToolCalls(from text: String) -> [AppToolCall] {
        // Try each parsing strategy in order of specificity
        if let calls = parseStandardJSON(from: text), !calls.isEmpty {
            return calls
        }

        if let calls = parseCodeBlockJSON(from: text), !calls.isEmpty {
            return calls
        }

        return []
    }

    /// Check if the text appears to contain a tool call.
    ///
    /// Lightweight check — cheaper than full parsing. Use to gate expensive
    /// JSON parsing only when needed.
    static func mightContainToolCall(_ text: String) -> Bool {
        text.contains("function_call") ||
        text.contains("\"name\"") && text.contains("\"arguments\"") ||
        text.contains("tool_call")
    }

    // MARK: - Parsing Strategies

    /// Parse standard JSON tool calls: `{"function_call": {"name": ..., "arguments": ...}}`
    private static func parseStandardJSON(from text: String) -> [AppToolCall]? {
        // Find all JSON objects in the text
        let jsonObjects = extractJSONObjects(from: text)

        var results: [AppToolCall] = []
        for json in jsonObjects {
            if let call = parseSingleToolCall(from: json) {
                results.append(call)
            }
        }

        return results.isEmpty ? nil : results
    }

    /// Parse tool calls wrapped in markdown code blocks.
    private static func parseCodeBlockJSON(from text: String) -> [AppToolCall]? {
        // Match ```json ... ``` or ``` ... ```
        let pattern = "```(?:json)?\\s*\\n?(.*?)\\n?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else {
            return nil
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var results: [AppToolCall] = []
        for match in matches {
            if match.numberOfRanges >= 2 {
                let codeContent = nsText.substring(with: match.range(at: 1))
                if let call = parseSingleToolCall(from: codeContent) {
                    results.append(call)
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    // MARK: - JSON Extraction

    /// Extract JSON object substrings from text by matching balanced braces.
    private static func extractJSONObjects(from text: String) -> [String] {
        var results: [String] = []
        let chars = Array(text)
        var i = 0

        while i < chars.count {
            if chars[i] == "{" {
                // Try to find the matching closing brace
                var depth = 0
                let start = i
                var inString = false
                var escaped = false

                for j in i..<chars.count {
                    if escaped {
                        escaped = false
                        continue
                    }
                    if chars[j] == "\\" && inString {
                        escaped = true
                        continue
                    }
                    if chars[j] == "\"" {
                        inString = !inString
                    }
                    if !inString {
                        if chars[j] == "{" { depth += 1 }
                        if chars[j] == "}" {
                            depth -= 1
                            if depth == 0 {
                                let jsonStr = String(chars[start...j])
                                results.append(jsonStr)
                                i = j + 1
                                break
                            }
                        }
                    }
                    if j == chars.count - 1 { i = j + 1 }
                }

                if depth != 0 { i += 1 }
            } else if chars[i] == "[" {
                // Try JSON array
                var depth = 0
                var inString = false
                var escaped = false

                for j in i..<chars.count {
                    if escaped {
                        escaped = false
                        continue
                    }
                    if chars[j] == "\\" && inString {
                        escaped = true
                        continue
                    }
                    if chars[j] == "\"" {
                        inString = !inString
                    }
                    if !inString {
                        if chars[j] == "[" { depth += 1 }
                        if chars[j] == "]" {
                            depth -= 1
                            if depth == 0 {
                                let jsonStr = String(chars[i...j])
                                // Try to parse as array of tool calls
                                if let data = jsonStr.data(using: .utf8),
                                   let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                                    for item in arr {
                                        if let jsonData = try? JSONSerialization.data(withJSONObject: item),
                                           let itemStr = String(data: jsonData, encoding: .utf8) {
                                            results.append(itemStr)
                                        }
                                    }
                                }
                                i = j + 1
                                break
                            }
                        }
                    }
                    if j == chars.count - 1 { i = j + 1 }
                }

                if depth != 0 { i += 1 }
            } else {
                i += 1
            }
        }

        return results
    }

    // MARK: - Single Tool Call Parsing

    /// Parse a single tool call from a JSON string.
    ///
    /// Supports these JSON shapes:
    /// - `{"function_call": {"name": "...", "arguments": {...}}}`
    /// - `{"name": "...", "arguments": {...}}`
    /// - `{"tool_calls": [{"function": {"name": "...", "arguments": {...}}}]}`
    private static func parseSingleToolCall(from jsonString: String) -> AppToolCall? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Shape 1: {"function_call": {"name": ..., "arguments": ...}}
        if let functionCall = json["function_call"] as? [String: Any],
           let name = functionCall["name"] as? String {
            let arguments = functionCall["arguments"] as? [String: Any] ?? [:]
            return AppToolCall(
                id: UUID().uuidString,
                toolName: name,
                arguments: arguments.mapValues { AnyCodable($0) }
            )
        }

        // Shape 2: {"name": ..., "arguments": ...} (direct)
        if let name = json["name"] as? String,
           json["arguments"] != nil {
            let arguments = json["arguments"] as? [String: Any] ?? [:]
            return AppToolCall(
                id: UUID().uuidString,
                toolName: name,
                arguments: arguments.mapValues { AnyCodable($0) }
            )
        }

        // Shape 3: {"tool_calls": [{"function": {"name": ..., "arguments": ...}}]}
        if let toolCalls = json["tool_calls"] as? [[String: Any]],
           let first = toolCalls.first,
           let function = first["function"] as? [String: Any],
           let name = function["name"] as? String {
            let arguments = function["arguments"] as? [String: Any] ?? [:]
            return AppToolCall(
                id: first["id"] as? String ?? UUID().uuidString,
                toolName: name,
                arguments: arguments.mapValues { AnyCodable($0) }
            )
        }

        return nil
    }

    // MARK: - System Prompt Generation

    /// Generate a tool-aware system prompt suffix that describes available tools
    /// in a format the model can use to generate function calls.
    ///
    /// - Parameter tools: The available tools.
    /// - Returns: A string to append to the system message, or nil if no tools.
    static func toolSystemPrompt(for tools: [any AppTool]) -> String? {
        guard !tools.isEmpty else { return nil }

        var prompt = "\n\nYou have access to the following tools:\n\n"

        for tool in tools {
            let schema = tool.parameterSchema.toJSONDict()
            let toolDef: [String: Any] = [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.toolDescription,
                    "parameters": schema,
                ],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: toolDef, options: [.sortedKeys]),
               let jsonStr = String(data: data, encoding: .utf8) {
                prompt += "\(jsonStr)\n"
            }
        }

        prompt += """

        When you need to use a tool, respond ONLY with a JSON object in this exact format — no other text:
        {"function_call": {"name": "tool_name", "arguments": {"param1": "value1"}}}

        IMPORTANT: You MUST use the appropriate tool for ANY mathematical calculation, unit conversion, or numeric computation. Do NOT compute results yourself — always delegate to the calculate or convert_units tool. When using the calculate tool, provide the expression as a string.
        """

        return prompt
    }
}
