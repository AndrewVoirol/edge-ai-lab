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

// MARK: - Built-In Eval Suites

/// Ships 4 default evaluation suites covering math, tool calling, reasoning, and multimodal.
///
/// These suites are designed to exercise the on-device tools registered in `ToolRegistry`
/// and validate model inference quality across different capability dimensions.
enum BuiltInEvalSuites {

    /// All built-in evaluation suites.
    static let allBuiltIn: [EvalSuite] = [
        mathAccuracy,
        toolCallingReliability,
        reasoning,
        multimodal,
    ]

    // MARK: - Math Accuracy

    /// Tests calculator and unit converter tool usage with 10 math-focused prompts.
    ///
    /// Validates that the model correctly identifies when to use the `calculate` and
    /// `convert_units` tools, and that the results are incorporated into the response.
    static let mathAccuracy = EvalSuite(
        name: "Math Accuracy",
        description: "Tests calculator and unit converter tool usage across arithmetic, algebra, and unit conversion problems.",
        category: .math,
        prompts: [
            EvalPrompt(
                prompt: "What is 247 * 38?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "Convert 72 degrees Fahrenheit to Celsius",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "What is 15% of 340?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "Calculate the square root of 144",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "How many kilometers is 26.2 miles?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "What is (125 + 375) / 10?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "Convert 2.5 kilograms to pounds",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "If I have 3 dozen eggs and use 17, how many are left?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "What is 1024 divided by 16?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "Convert 100 meters per second to miles per hour",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Tool Calling Reliability

    /// Tests tool selection accuracy with 12 prompts spanning all registered tools.
    ///
    /// Includes positive tests (should call specific tools), adversarial tests
    /// (should NOT call tools), and multi-tool chain tests.
    static let toolCallingReliability = EvalSuite(
        name: "Tool Calling Reliability",
        description: "Tests tool selection accuracy across all registered tools, including adversarial prompts and multi-tool chains.",
        category: .toolCalling,
        prompts: [
            // Date/Time tool
            EvalPrompt(
                prompt: "What time is it right now?",
                expectedBehavior: .toolCall(toolName: "get_date_time")
            ),
            EvalPrompt(
                prompt: "What day of the week is it today?",
                expectedBehavior: .toolCall(toolName: "get_date_time")
            ),

            // Device info tool
            EvalPrompt(
                prompt: "How much RAM does this device have?",
                expectedBehavior: .toolCall(toolName: "get_device_info")
            ),
            EvalPrompt(
                prompt: "What kind of processor does this device use?",
                expectedBehavior: .toolCall(toolName: "get_device_info")
            ),

            // System health tool
            EvalPrompt(
                prompt: "What's the thermal state of this device?",
                expectedBehavior: .toolCall(toolName: "system_health")
            ),
            EvalPrompt(
                prompt: "How much battery does this device have left?",
                expectedBehavior: .toolCall(toolName: "system_health")
            ),

            // Text analyzer tool
            EvalPrompt(
                prompt: "Analyze this text: 'Hello world, this is a test of the text analyzer tool.'",
                expectedBehavior: .toolCall(toolName: "analyze_text")
            ),
            EvalPrompt(
                prompt: "Count the words in this sentence: 'The quick brown fox jumps over the lazy dog'",
                expectedBehavior: .toolCall(toolName: "analyze_text")
            ),

            // Adversarial: should NOT call calculator
            EvalPrompt(
                prompt: "Write me a poem about calculators",
                expectedBehavior: .nonEmpty
            ),
            EvalPrompt(
                prompt: "Explain the concept of addition to a child",
                expectedBehavior: .nonEmpty
            ),

            // Multi-tool chain
            EvalPrompt(
                prompt: "What's 15% of the current year?",
                expectedBehavior: .toolCallChain(["get_date_time", "calculate"]),
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "Check the device thermal state and tell me the temperature in Fahrenheit if it were a number from 1-4",
                expectedBehavior: .toolCallChain(["system_health", "convert_units"]),
                timeoutSeconds: 90
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Reasoning

    /// Tests logic and multi-step deduction with 8 reasoning-focused prompts.
    ///
    /// Includes logic puzzles with known answers, syllogisms, and general
    /// coherence checks.
    static let reasoning = EvalSuite(
        name: "Reasoning",
        description: "Tests logical reasoning, deduction, and multi-step problem solving with puzzles and word problems.",
        category: .reasoning,
        prompts: [
            // Logic puzzles with known answers
            EvalPrompt(
                prompt: "If all roses are flowers and some flowers fade quickly, can we conclude that some roses fade quickly?",
                expectedBehavior: .containsText("no"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "A bat and ball cost $1.10 total. The bat costs $1.00 more than the ball. How much does the ball cost?",
                expectedBehavior: .containsText("5"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "If it takes 5 machines 5 minutes to make 5 widgets, how long would it take 100 machines to make 100 widgets?",
                expectedBehavior: .containsText("5"),
                timeoutSeconds: 45
            ),

            // Multi-step deduction
            EvalPrompt(
                prompt: "Alice is taller than Bob. Charlie is shorter than Bob. David is taller than Alice. Who is the tallest?",
                expectedBehavior: .containsText("David"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "In a room of 23 people, what is the approximate probability that two share a birthday? Answer with just the percentage.",
                expectedBehavior: .matchesRegex("5[0-2]%?"),
                timeoutSeconds: 45
            ),

            // Counting and pattern recognition
            EvalPrompt(
                prompt: "What comes next in this sequence: 2, 6, 12, 20, 30, ?",
                expectedBehavior: .containsText("42"),
                timeoutSeconds: 45
            ),

            // General coherence
            EvalPrompt(
                prompt: "Explain why the sky appears blue in exactly three sentences.",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "Name three things that are true about the number zero.",
                expectedBehavior: .nonEmpty,
                timeoutSeconds: 45
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Multimodal

    /// Tests vision and audio capabilities with 6 multimodal prompts.
    ///
    /// **Note**: This suite ships with nil image/audio data placeholders.
    /// Models that don't support the required modality will skip those prompts
    /// (the eval runner marks them as failed with a descriptive reason).
    /// To run these tests with real data, create a custom suite with actual
    /// image/audio payloads.
    static let multimodal = EvalSuite(
        name: "Multimodal",
        description: "Tests vision and audio capabilities. Ships with placeholder prompts — requires actual image/audio data for meaningful evaluation.",
        category: .multimodal,
        prompts: [
            // Image description tasks (nil imageData placeholder)
            EvalPrompt(
                prompt: "Describe what you see in this image in detail.",
                expectedBehavior: .nonEmpty,
                imageData: nil,
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "What colors are dominant in this image?",
                expectedBehavior: .nonEmpty,
                imageData: nil,
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "Is there any text visible in this image? If so, what does it say?",
                expectedBehavior: .nonEmpty,
                imageData: nil,
                timeoutSeconds: 90
            ),

            // Audio understanding tasks (nil audioData placeholder)
            EvalPrompt(
                prompt: "What is being said in this audio clip?",
                expectedBehavior: .nonEmpty,
                audioData: nil,
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "Describe the sounds you hear in this audio.",
                expectedBehavior: .nonEmpty,
                audioData: nil,
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "What language is being spoken in this audio?",
                expectedBehavior: .nonEmpty,
                audioData: nil,
                timeoutSeconds: 90
            ),
        ],
        isBuiltIn: true
    )
}
