// Copyright 2026 Andrew Voirol. Apache-2.0

import Foundation
import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

/// Tests for `BuiltInEvalSuites.gemma4Specific` — validates suite construction
/// and tool chain references against `ToolRegistry`.
@Suite("Gemma 4 Eval Suite")
struct Gemma4EvalTests {

    // MARK: - Suite Construction

    @Test("Suite has 12 prompts")
    func suitePromptCount() {
        let suite = BuiltInEvalSuites.gemma4Specific
        #expect(suite.prompts.count == 12)
    }

    @Test("Suite has correct metadata")
    func suiteMetadata() {
        let suite = BuiltInEvalSuites.gemma4Specific
        #expect(suite.name == "Gemma 4 Capabilities")
        #expect(suite.category == .general)
        #expect(suite.isBuiltIn == true)
        #expect(!suite.description.isEmpty)
    }

    // MARK: - Tool Name Validation

    @Test("All tool names reference tools in ToolRegistry")
    func toolNamesAreValid() {
        let registeredToolNames = Set(ToolRegistry.defaultTools.map(\.name))
        let suite = BuiltInEvalSuites.gemma4Specific

        for prompt in suite.prompts {
            switch prompt.expectedBehavior {
            case .toolCall(toolName: let name):
                #expect(
                    registeredToolNames.contains(name),
                    "Tool '\(name)' in prompt '\(prompt.truncatedPrompt)' is not registered in ToolRegistry"
                )
            case .toolCallWithArgs(toolName: let name, key: _, expectedValue: _):
                #expect(
                    registeredToolNames.contains(name),
                    "Tool '\(name)' in prompt '\(prompt.truncatedPrompt)' is not registered in ToolRegistry"
                )
            case .toolCallChain(let tools):
                for toolName in tools {
                    #expect(
                        registeredToolNames.contains(toolName),
                        "Tool '\(toolName)' in chain for prompt '\(prompt.truncatedPrompt)' is not registered in ToolRegistry"
                    )
                }
            default:
                break
            }
        }
    }

    // MARK: - Behavioral Mix

    @Test("Suite contains multi-tool chain prompts")
    func suiteHasToolChainPrompts() {
        let suite = BuiltInEvalSuites.gemma4Specific
        let hasChain = suite.prompts.contains {
            if case .toolCallChain = $0.expectedBehavior { return true }
            return false
        }
        #expect(hasChain, "Gemma 4 suite should include tool chain prompts")
    }

    @Test("Suite contains adversarial nonEmpty prompts")
    func suiteHasAdversarialPrompts() {
        let suite = BuiltInEvalSuites.gemma4Specific
        let hasNonEmpty = suite.prompts.contains {
            if case .nonEmpty = $0.expectedBehavior { return true }
            return false
        }
        #expect(hasNonEmpty, "Gemma 4 suite should include adversarial .nonEmpty prompts")
    }

    @Test("Suite contains single tool call prompts")
    func suiteHasSingleToolCallPrompts() {
        let suite = BuiltInEvalSuites.gemma4Specific
        let hasToolCall = suite.prompts.contains {
            if case .toolCall = $0.expectedBehavior { return true }
            return false
        }
        #expect(hasToolCall, "Gemma 4 suite should include single .toolCall prompts")
    }

    @Test("Suite contains reasoning prompts with containsAny")
    func suiteHasReasoningPrompts() {
        let suite = BuiltInEvalSuites.gemma4Specific
        let hasContainsAny = suite.prompts.contains {
            if case .containsAny = $0.expectedBehavior { return true }
            return false
        }
        #expect(hasContainsAny, "Gemma 4 suite should include .containsAny reasoning prompts")
    }
}
