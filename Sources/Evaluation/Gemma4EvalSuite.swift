// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation

// MARK: - Gemma 4 Capabilities Eval Suite

extension BuiltInEvalSuites {

    /// Tests capabilities specific to Gemma 4 models including advanced tool use,
    /// multi-step reasoning, and thinking mode.
    ///
    /// Covers multi-tool chains, tool avoidance (adversarial), correct tool selection,
    /// complex reasoning with known answers, multi-step math, context retention,
    /// and combined instruction + tool prompts.
    static let gemma4Specific = EvalSuite(
        name: "Gemma 4 Capabilities",
        description: "Tests capabilities specific to Gemma 4 models including advanced tool use, multi-step reasoning, and thinking mode.",
        category: .general,
        prompts: [
            // 1. Multi-tool chain: calculate then device info
            EvalPrompt(
                prompt: "What is 15% of 247? Then tell me what device I'm using.",
                expectedBehavior: .toolCallChain(["calculate", "get_device_info"]),
                timeoutSeconds: 90
            ),

            // 2. Multi-tool chain: datetime then system health
            EvalPrompt(
                prompt: "What time is it and what's the system health status?",
                expectedBehavior: .toolCallChain(["get_current_datetime", "get_system_health"]),
                timeoutSeconds: 90
            ),

            // 3. Tool with follow-up reasoning
            EvalPrompt(
                prompt: "Calculate 2 to the power of 10, then explain why that number is important in computing",
                expectedBehavior: .containsAll(["1024"]),
                timeoutSeconds: 90
            ),

            // 4. Should NOT call tools — general knowledge
            EvalPrompt(
                prompt: "Explain what photosynthesis is in simple terms",
                expectedBehavior: .nonEmpty
            ),

            // 5. Should NOT call tools — factual recall
            EvalPrompt(
                prompt: "What are the three laws of thermodynamics?",
                expectedBehavior: .nonEmpty
            ),

            // 6. Correct tool selection — calculator
            EvalPrompt(
                prompt: "What's 342 divided by 17?",
                expectedBehavior: .toolCall(toolName: "calculate")
            ),

            // 7. Correct tool selection — unit converter
            EvalPrompt(
                prompt: "Convert 100 kilometers to miles",
                expectedBehavior: .anyToolCall
            ),

            // 8. Correct tool selection — text analyzer
            EvalPrompt(
                prompt: "How many words are in: 'The quick brown fox jumps'",
                expectedBehavior: .toolCall(toolName: "analyze_text")
            ),

            // 9. Complex reasoning — probability
            EvalPrompt(
                prompt: "If I have 3 red balls and 5 blue balls, what is the probability of picking 2 red balls in a row without replacement?",
                expectedBehavior: .containsAny(["3/28", "0.107", "10.7%", "3 out of 28"]),
                timeoutSeconds: 90
            ),

            // 10. Multi-step math — discount + coupon
            EvalPrompt(
                prompt: "A store has a 20% off sale. I have a $10 coupon. What do I pay for a $80 item if the coupon applies after the discount?",
                expectedBehavior: .containsAny(["$54", "54 dollars", "54.00"]),
                timeoutSeconds: 90
            ),

            // 11. Context retention
            EvalPrompt(
                prompt: "My name is Alice. I have a dog named Max. What is my dog's name?",
                expectedBehavior: .containsText("Max")
            ),

            // 12. Instruction + tool combined
            EvalPrompt(
                prompt: "Use the calculator to find the square root of 144, then write a haiku about that number",
                expectedBehavior: .containsAll(["12"]),
                timeoutSeconds: 90
            ),
        ],
        isBuiltIn: true
    )
}
