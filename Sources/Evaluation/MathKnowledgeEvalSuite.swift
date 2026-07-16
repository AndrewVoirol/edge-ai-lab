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

extension BuiltInEvalSuites {

    // MARK: - Math Knowledge

    /// Tests mathematical knowledge using text-based scoring.
    ///
    /// Unlike "Math Accuracy" (which scores on tool invocation), this suite checks
    /// whether the model's **text response** contains the correct answer. This makes
    /// it compatible with ALL inference engines, including GGUF and MLX which don't
    /// support tool calling.
    ///
    /// Prompts are a representative sample covering arithmetic, percentages, algebra,
    /// unit conversions, and word problems.
    static let mathKnowledge = EvalSuite(
        name: "Math Knowledge",
        description: "Tests mathematical reasoning via text-based scoring. Compatible with all engines (no tool calling required).",
        category: .math,
        prompts: [
            // Basic arithmetic
            EvalPrompt(
                prompt: "What is 247 * 38? Give just the number.",
                expectedBehavior: .containsText("9386"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "What is 1024 divided by 16? Give just the number.",
                expectedBehavior: .containsText("64"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "What is (125 + 375) / 10? Give just the number.",
                expectedBehavior: .containsText("50"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "Calculate the square root of 144.",
                expectedBehavior: .containsText("12"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "What is 2 to the power of 10?",
                expectedBehavior: .containsText("1024"),
                timeoutSeconds: 30
            ),

            // Percentages
            EvalPrompt(
                prompt: "What is 15% of 340?",
                expectedBehavior: .containsText("51"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "A restaurant bill is $84. What is an 18% tip? Give the dollar amount.",
                expectedBehavior: .containsAny(["15.12", "$15.12"]),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "If a stock goes from $120 to $156, what is the percentage increase?",
                expectedBehavior: .containsText("30"),
                timeoutSeconds: 30
            ),

            // Word problems
            EvalPrompt(
                prompt: "If I have 3 dozen eggs and use 17, how many are left?",
                expectedBehavior: .containsText("19"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "A shirt costs $45 and is on sale for 20% off. What is the sale price?",
                expectedBehavior: .containsAny(["36", "$36"]),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "If a train travels 180 miles in 3 hours, what is its average speed in miles per hour?",
                expectedBehavior: .containsText("60"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "I bought 4 notebooks at $3.75 each and 2 pens at $1.50 each. What is the total cost?",
                expectedBehavior: .containsAny(["18", "$18"]),
                timeoutSeconds: 30
            ),

            // Multi-step
            EvalPrompt(
                prompt: "What is ((42 + 18) * 3) - 50? Give just the number.",
                expectedBehavior: .containsText("130"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "If a rectangle has a length of 15 and width of 8, what is its area?",
                expectedBehavior: .containsText("120"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "What is the average of 85, 92, 78, 96, and 88? Give just the number.",
                expectedBehavior: .containsAny(["87.8", "87"]),
                timeoutSeconds: 30
            ),

            // Unit conversions (text-based answers)
            EvalPrompt(
                prompt: "Convert 72 degrees Fahrenheit to Celsius. Give the number rounded to one decimal.",
                expectedBehavior: .containsText("22.2"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "How many kilometers is 26.2 miles? Round to one decimal.",
                expectedBehavior: .containsAny(["42.1", "42.2"]),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "How many inches are in 3 yards?",
                expectedBehavior: .containsText("108"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "How many grams are in 3.5 kilograms?",
                expectedBehavior: .containsText("3500"),
                timeoutSeconds: 30
            ),
            EvalPrompt(
                prompt: "Convert 2.5 kilograms to pounds. Round to one decimal.",
                expectedBehavior: .containsText("5.5"),
                timeoutSeconds: 30
            ),
        ],
        isBuiltIn: true
    )
}
