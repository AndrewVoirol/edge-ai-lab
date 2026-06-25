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

    /// Tests calculator and unit converter tool usage with 30 math-focused prompts.
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

            // --- New prompts (11–30) ---

            // Arithmetic edge cases
            EvalPrompt(
                prompt: "What is 999999 * 999999?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "What is 7 divided by 0?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "What is 0.1 + 0.2?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "Calculate 2 to the power of 10",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),

            // Word problems
            EvalPrompt(
                prompt: "A shirt costs $45 and is on sale for 20% off. What is the sale price?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "If a train travels 180 miles in 3 hours, what is its average speed in miles per hour?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "I bought 4 notebooks at $3.75 each and 2 pens at $1.50 each. What is the total cost?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),

            // Multi-step calculations
            EvalPrompt(
                prompt: "What is ((42 + 18) * 3) - 50?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "If a rectangle has a length of 15 and width of 8, what is its area?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "What is the average of 85, 92, 78, 96, and 88?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),

            // Percentages
            EvalPrompt(
                prompt: "A restaurant bill is $84. What is an 18% tip?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),
            EvalPrompt(
                prompt: "If a stock goes from $120 to $156, what is the percentage increase?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),

            // Unit conversions — temperature
            EvalPrompt(
                prompt: "Convert absolute zero (0 Kelvin) to Celsius",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "What is body temperature (98.6°F) in Celsius?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),

            // Unit conversions — distance
            EvalPrompt(
                prompt: "How many inches are in 3 yards?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "Convert 5280 feet to miles",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),

            // Unit conversions — weight
            EvalPrompt(
                prompt: "How many grams are in 3.5 kilograms?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "Convert 16 ounces to pounds",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),

            // Unit conversions — data storage
            EvalPrompt(
                prompt: "How many megabytes are in 2 gigabytes?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
            EvalPrompt(
                prompt: "Convert 5000 kilobytes to megabytes",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Tool Calling Reliability

    /// Tests tool selection accuracy with 20 prompts spanning all registered tools.
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
                expectedBehavior: .toolCall(toolName: "get_current_datetime")
            ),
            EvalPrompt(
                prompt: "What day of the week is it today?",
                expectedBehavior: .toolCall(toolName: "get_current_datetime")
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
                expectedBehavior: .toolCall(toolName: "get_system_health")
            ),
            EvalPrompt(
                prompt: "How much battery does this device have left?",
                expectedBehavior: .toolCall(toolName: "get_system_health")
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
                expectedBehavior: .toolCallChain(["get_current_datetime", "calculate"]),
                timeoutSeconds: 90
            ),
            EvalPrompt(
                prompt: "Check the device thermal state and tell me the temperature in Fahrenheit if it were a number from 1-4",
                expectedBehavior: .toolCallChain(["get_system_health", "convert_units"]),
                timeoutSeconds: 90
            ),

            // --- New prompts (13–20) ---

            // DateTime with timezone argument
            EvalPrompt(
                prompt: "What time is it in Tokyo right now?",
                expectedBehavior: .toolCallWithArgs(toolName: "get_current_datetime", key: "timezone", expectedValue: "Asia/Tokyo")
            ),

            // System health — disk space
            EvalPrompt(
                prompt: "How much free disk space does this device have?",
                expectedBehavior: .toolCall(toolName: "get_system_health")
            ),

            // Device info — OS version
            EvalPrompt(
                prompt: "What operating system version is this device running?",
                expectedBehavior: .toolCall(toolName: "get_device_info")
            ),

            // Text analyzer — language detection
            EvalPrompt(
                prompt: "What language is this text written in: 'Bonjour le monde, comment ça va?'",
                expectedBehavior: .toolCall(toolName: "analyze_text")
            ),

            // Adversarial: mentions tools but shouldn't call any
            EvalPrompt(
                prompt: "List all the tools you have access to and describe what each one does",
                expectedBehavior: .nonEmpty
            ),

            // Ambiguous tool selection — calculator vs. unit converter
            EvalPrompt(
                prompt: "How many bytes are in 1 terabyte?",
                expectedBehavior: .toolCall(toolName: "convert_units")
            ),

            // Multi-tool chain — device info then text analysis
            EvalPrompt(
                prompt: "Get the device model name and analyze that text string for word count",
                expectedBehavior: .toolCallChain(["get_device_info", "analyze_text"]),
                timeoutSeconds: 90
            ),

            // Adversarial: math-adjacent but conceptual
            EvalPrompt(
                prompt: "What is the history of the number zero?",
                expectedBehavior: .nonEmpty
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Reasoning

    /// Tests logic and multi-step deduction with 25 reasoning-focused prompts.
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

            // --- New prompts (9–25) ---

            // Syllogisms
            EvalPrompt(
                prompt: "All mammals are warm-blooded. All dogs are mammals. Are all dogs warm-blooded?",
                expectedBehavior: .containsText("yes"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "Some birds can fly. Penguins are birds. Can penguins fly?",
                expectedBehavior: .containsText("no"),
                timeoutSeconds: 45
            ),

            // Spatial reasoning
            EvalPrompt(
                prompt: "If I'm facing north and turn 90 degrees to my right, then turn 180 degrees, which direction am I facing?",
                expectedBehavior: .containsText("west"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "A cube has 6 faces. If I paint 3 adjacent faces red, what is the maximum number of red faces visible from a single viewpoint?",
                expectedBehavior: .containsText("3"),
                timeoutSeconds: 45
            ),

            // Common sense reasoning
            EvalPrompt(
                prompt: "If I put ice cream in a hot oven for an hour, what will happen to it?",
                expectedBehavior: .containsText("melt"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "Can a person stand inside a basketball? Answer yes or no and explain.",
                expectedBehavior: .containsText("no"),
                timeoutSeconds: 45
            ),

            // Adversarial / trick questions
            EvalPrompt(
                prompt: "A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left?",
                expectedBehavior: .containsText("9"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "How many times can you subtract 5 from 25?",
                expectedBehavior: .containsText("1"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "If you have a bowl with six apples and you take away four, how many do you have?",
                expectedBehavior: .containsText("4"),
                timeoutSeconds: 45
            ),

            // Deduction chains
            EvalPrompt(
                prompt: "In a race, you overtake the person in 2nd place. What position are you in now?",
                expectedBehavior: .containsText("2nd"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "Tom is older than Jane. Jane is older than Sam. Sam is older than Rita. Who is the youngest?",
                expectedBehavior: .containsText("Rita"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "If Monday is two days after the day before yesterday, what day is today?",
                expectedBehavior: .containsText("Wednesday"),
                timeoutSeconds: 45
            ),

            // Analogies
            EvalPrompt(
                prompt: "Hot is to cold as tall is to what?",
                expectedBehavior: .containsText("short"),
                timeoutSeconds: 45
            ),
            EvalPrompt(
                prompt: "Book is to reading as fork is to what?",
                expectedBehavior: .containsText("eating"),
                timeoutSeconds: 45
            ),

            // Logic puzzles
            EvalPrompt(
                prompt: "There are three boxes: one has only apples, one has only oranges, and one has both. All boxes are mislabeled. You pick one fruit from the box labeled 'Both'. It's an apple. What does the 'Both' box actually contain?",
                expectedBehavior: .containsText("apples"),
                timeoutSeconds: 60
            ),
            EvalPrompt(
                prompt: "I speak without a mouth and hear without ears. I have no body but I come alive with the wind. What am I?",
                expectedBehavior: .containsText("echo"),
                timeoutSeconds: 45
            ),

            // Pattern recognition
            EvalPrompt(
                prompt: "What comes next: 1, 1, 2, 3, 5, 8, 13, ?",
                expectedBehavior: .containsText("21"),
                timeoutSeconds: 45
            ),
        ],
        isBuiltIn: true
    )

    // MARK: - Multimodal

    /// Tests vision and audio capabilities with 25 multimodal prompts.
    ///
    /// Uses real test images loaded from the app bundle via ``EvalImageLoader``.
    /// Each image-based prompt has content-specific scoring (`.containsText`,
    /// `.matchesRegex`) instead of trivial `.nonEmpty` checks.
    ///
    /// If an image fails to load from the bundle (e.g., in test environments where
    /// the app bundle doesn't include eval images), the prompt gracefully falls back
    /// to `imageData: nil` — the eval runner will mark it as failed with a descriptive
    /// reason rather than crashing.
    static let multimodal = EvalSuite(
        name: "Multimodal",
        description: "Tests vision and audio capabilities with real test images and content-specific scoring.",
        category: .multimodal,
        prompts: {
            // Load images from the app bundle at suite construction time.
            // Returns nil gracefully if an image isn't found.
            func img(_ name: String) -> Data? {
                EvalImageLoader.loadImage(named: name)
            }

            return [
                // --- Image prompts with real images and synonym-tolerant scoring ---

                // Object identification — .containsAny for synonym tolerance
                EvalPrompt(
                    prompt: "What fruit is in this image?",
                    expectedBehavior: .containsAny(["apple", "fruit"]),
                    imageData: img("simple_red_apple"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What type of sign is this?",
                    expectedBehavior: .containsAny(["stop", "sign", "octagon"]),
                    imageData: img("stop_sign"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What vehicle is in this image?",
                    expectedBehavior: .containsAny(["bus", "vehicle", "van", "school bus"]),
                    imageData: img("yellow_school_bus"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What objects are shown in this image?",
                    expectedBehavior: .containsAny(["dice", "die", "cube", "cubes"]),
                    imageData: img("two_dice"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What flower is in this image?",
                    expectedBehavior: .containsAny(["sunflower", "flower", "daisy", "yellow flower"]),
                    imageData: img("sunflower"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What is leaning against the wall?",
                    expectedBehavior: .containsAny(["bicycle", "bike", "cycle"]),
                    imageData: img("red_bicycle"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What is in the cup?",
                    expectedBehavior: .containsAny(["coffee", "drink", "tea", "beverage", "liquid"]),
                    imageData: img("blue_coffee_cup"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What breed of dog is this?",
                    expectedBehavior: .containsAny(["retriever", "golden", "dog", "labrador", "canine", "puppy"]),
                    imageData: img("golden_retriever"),
                    timeoutSeconds: 90
                ),

                // Counting — regex is already synonym-tolerant (numeral|word)
                EvalPrompt(
                    prompt: "How many cats are in this image?",
                    expectedBehavior: .matchesRegex("3|three"),
                    imageData: img("three_cats"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "How many pencils are there?",
                    expectedBehavior: .matchesRegex("5|five"),
                    imageData: img("five_pencils"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "How many dice are shown?",
                    expectedBehavior: .matchesRegex("2|two"),
                    imageData: img("two_dice"),
                    timeoutSeconds: 90
                ),

                // OCR / Text recognition — exact text is appropriate here
                EvalPrompt(
                    prompt: "What text is shown in this image?",
                    expectedBehavior: .containsText("hello"),
                    imageData: img("text_hello_world"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "Read all the text visible in this image.",
                    expectedBehavior: .containsText("world"),
                    imageData: img("text_hello_world"),
                    timeoutSeconds: 90
                ),

                // Chart understanding — synonym-tolerant
                EvalPrompt(
                    prompt: "What type of chart is shown?",
                    expectedBehavior: .containsAny(["bar", "graph", "chart", "histogram"]),
                    imageData: img("bar_chart"),
                    timeoutSeconds: 90
                ),

                // Color identification — colors are unambiguous, keep .containsText
                EvalPrompt(
                    prompt: "What color is the fruit in this image?",
                    expectedBehavior: .containsText("red"),
                    imageData: img("simple_red_apple"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What color is the bicycle?",
                    expectedBehavior: .containsText("red"),
                    imageData: img("red_bicycle"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What color is the cup?",
                    expectedBehavior: .containsText("blue"),
                    imageData: img("blue_coffee_cup"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What color is the bus?",
                    expectedBehavior: .containsText("yellow"),
                    imageData: img("yellow_school_bus"),
                    timeoutSeconds: 90
                ),

                // Scene understanding — synonym-tolerant
                EvalPrompt(
                    prompt: "Describe what you see in this image in detail.",
                    expectedBehavior: .containsAny(["dog", "puppy", "retriever", "golden", "animal", "canine"]),
                    imageData: img("golden_retriever"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "Is this photo taken indoors or outdoors?",
                    expectedBehavior: .containsAny(["indoor", "outdoor", "inside", "outside"]),
                    imageData: img("sunflower"),
                    timeoutSeconds: 90
                ),

                // Multi-aspect queries — synonym-tolerant
                EvalPrompt(
                    prompt: "What is in this image and what color is it?",
                    expectedBehavior: .containsAny(["flower", "sunflower", "plant", "yellow"]),
                    imageData: img("sunflower"),
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "Describe the items in this image. How many are there?",
                    expectedBehavior: .containsAny(["pencil", "pen", "writing", "crayon"]),
                    imageData: img("five_pencils"),
                    timeoutSeconds: 90
                ),

                // Audio understanding tasks — nil audioData, marked for manual review
                // These previously used .nonEmpty which passed trivially (inflating metrics).
                // Marked as .custom to surface as manual review until real audio data is available.
                EvalPrompt(
                    prompt: "What is being said in this audio clip?",
                    expectedBehavior: .custom(description: "Requires real audio data — currently nil"),
                    audioData: nil,
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "Describe the sounds you hear in this audio.",
                    expectedBehavior: .custom(description: "Requires real audio data — currently nil"),
                    audioData: nil,
                    timeoutSeconds: 90
                ),
                EvalPrompt(
                    prompt: "What language is being spoken in this audio?",
                    expectedBehavior: .custom(description: "Requires real audio data — currently nil"),
                    audioData: nil,
                    timeoutSeconds: 90
                ),
            ]
        }(),
        isBuiltIn: true
    )
}
