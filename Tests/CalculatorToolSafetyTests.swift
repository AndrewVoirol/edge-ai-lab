// Copyright 2026 Andrew Voirol. Apache-2.0

import Testing

#if os(iOS)
@testable import EdgeAILab_iOS
#elseif os(macOS)
@testable import EdgeAILab_macOS
#endif

// MARK: - CalculatorValidation.validateStructure Tests

/// Tests for the structural validation layer that prevents uncatchable
/// `NSInvalidArgumentException` crashes from `NSExpression(format:)`.
@Suite("CalculatorValidation")
struct CalculatorToolSafetyTests {

    // MARK: - Valid Expressions (should return nil)

    @Test("Valid: simple addition")
    func validSimpleAddition() {
        #expect(CalculatorValidation.validateStructure("2.0 + 3.0") == nil)
    }

    @Test("Valid: parenthesized expression")
    func validParenthesized() {
        #expect(CalculatorValidation.validateStructure("(2.0 + 3.0) * 4.0") == nil)
    }

    @Test("Valid: single number")
    func validSingleNumber() {
        #expect(CalculatorValidation.validateStructure("2.0") == nil)
    }

    @Test("Valid: negative number")
    func validNegativeNumber() {
        #expect(CalculatorValidation.validateStructure("-3.0") == nil)
    }

    @Test("Valid: negation after operator (3 * -2)")
    func validNegationAfterOperator() {
        #expect(CalculatorValidation.validateStructure("3.0 * -2.0") == nil)
    }

    @Test("Valid: nested parentheses")
    func validNestedParens() {
        #expect(CalculatorValidation.validateStructure("((1.0 + 2.0) * (3.0 - 4.0))") == nil)
    }

    @Test("Valid: leading plus")
    func validLeadingPlus() {
        #expect(CalculatorValidation.validateStructure("+5.0") == nil)
    }

    // MARK: - Empty / Whitespace (should return error)

    @Test("Reject: empty string")
    func rejectEmpty() {
        #expect(CalculatorValidation.validateStructure("") != nil)
    }

    @Test("Reject: whitespace only")
    func rejectWhitespace() {
        #expect(CalculatorValidation.validateStructure("   ") != nil)
    }

    // MARK: - Unbalanced Parentheses (should return error)

    @Test("Reject: missing closing paren")
    func rejectMissingCloseParen() {
        let result = CalculatorValidation.validateStructure("(2.0 + 3.0")
        #expect(result != nil)
        #expect(result!.contains("Unbalanced"))
    }

    @Test("Reject: missing opening paren")
    func rejectMissingOpenParen() {
        let result = CalculatorValidation.validateStructure("2.0 + 3.0)")
        #expect(result != nil)
        #expect(result!.contains("Unbalanced"))
    }

    @Test("Reject: reversed parens")
    func rejectReversedParens() {
        let result = CalculatorValidation.validateStructure(")2.0 + 3.0(")
        #expect(result != nil)
        #expect(result!.contains("Unbalanced"))
    }

    // MARK: - Leading Operators (should return error)

    @Test("Reject: leading *")
    func rejectLeadingMultiply() {
        let result = CalculatorValidation.validateStructure("* 5.0")
        #expect(result != nil)
        #expect(result!.contains("starts with"))
    }

    @Test("Reject: leading /")
    func rejectLeadingDivide() {
        let result = CalculatorValidation.validateStructure("/ 5.0")
        #expect(result != nil)
        #expect(result!.contains("starts with"))
    }

    // MARK: - Trailing Operators (should return error)

    @Test("Reject: trailing +")
    func rejectTrailingPlus() {
        let result = CalculatorValidation.validateStructure("3.0 +")
        #expect(result != nil)
        #expect(result!.contains("ends with"))
    }

    @Test("Reject: trailing *")
    func rejectTrailingMultiply() {
        let result = CalculatorValidation.validateStructure("5.0 *")
        #expect(result != nil)
        #expect(result!.contains("ends with"))
    }

    @Test("Reject: trailing -")
    func rejectTrailingMinus() {
        let result = CalculatorValidation.validateStructure("3.0 -")
        #expect(result != nil)
        #expect(result!.contains("ends with"))
    }

    @Test("Reject: trailing /")
    func rejectTrailingDivide() {
        let result = CalculatorValidation.validateStructure("5.0 /")
        #expect(result != nil)
        #expect(result!.contains("ends with"))
    }

    // MARK: - Consecutive Operators (should return error, except negation)

    @Test("Reject: consecutive ++")
    func rejectDoublePlus() {
        let result = CalculatorValidation.validateStructure("3.0 ++ 4.0")
        #expect(result != nil)
        #expect(result!.contains("Consecutive"))
    }

    @Test("Reject: consecutive */")
    func rejectMultiplyDivide() {
        let result = CalculatorValidation.validateStructure("3.0 */ 2.0")
        #expect(result != nil)
        #expect(result!.contains("Consecutive"))
    }

    @Test("Reject: consecutive *+")
    func rejectMultiplyPlus() {
        let result = CalculatorValidation.validateStructure("3.0 *+ 2.0")
        #expect(result != nil)
        #expect(result!.contains("Consecutive"))
    }

    @Test("Allow: operator followed by minus (negation)")
    func allowOperatorThenMinus() {
        // "3 * -2" is valid — the minus is negation, not a binary operator
        #expect(CalculatorValidation.validateStructure("3.0 * -2.0") == nil)
        #expect(CalculatorValidation.validateStructure("3.0 + -2.0") == nil)
    }

    // MARK: - No Digits (should return error)

    @Test("Reject: only operators")
    func rejectOnlyOperators() {
        let result = CalculatorValidation.validateStructure("+-*/")
        #expect(result != nil)
        #expect(result!.contains("no numbers"))
    }

    @Test("Reject: only dots")
    func rejectOnlyDots() {
        let result = CalculatorValidation.validateStructure("...")
        #expect(result != nil)
        #expect(result!.contains("no numbers"))
    }

    @Test("Reject: empty parens")
    func rejectEmptyParens() {
        let result = CalculatorValidation.validateStructure("()")
        #expect(result != nil)
        #expect(result!.contains("no numbers"))
    }

    @Test("Reject: parens with only space")
    func rejectParensWithSpace() {
        let result = CalculatorValidation.validateStructure("( )")
        #expect(result != nil)
        #expect(result!.contains("no numbers"))
    }
}
