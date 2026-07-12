import Foundation
import SwiftSyntax
import SwiftParser

struct ExtractedData: Codable {
    var stateVariables: [StateVariable] = []
    var conditionals: [Conditional] = []
    var hiddenElements: [HiddenElement] = []
    var compilerDirectives: [CompilerDirective] = []
    var accessibilityModifiers: [Modifier] = []
    var stylingModifiers: [Modifier] = []
    var layoutModifiers: [Modifier] = []
    var hardcodedStrings: [HardcodedString] = []
    var interactiveElements: [InteractiveElement] = []
    var stackAlignments: [StackAlignment] = []
}

struct StateVariable: Codable {
    var name: String
    var propertyWrapper: String
    var type: String?
}

struct Conditional: Codable {
    var condition: String
    var trueBranchElements: [String]
    var falseBranchElements: [String]
    var kind: String // "if", "switch", "ternary"
}

struct HiddenElement: Codable {
    var element: String
    var hidingMethod: String // "opacity", "frame"
    var condition: String?
}

struct Modifier: Codable {
    var name: String
    var arguments: String
    var base: String
}

struct CompilerDirective: Codable {
    var condition: String
    var elements: [String]
}

struct HardcodedString: Codable {
    var text: String
}

struct InteractiveElement: Codable {
    var type: String
    var description: String
}

struct StackAlignment: Codable {
    var stackType: String
    var alignment: String
}

class ViewVisitor: SyntaxVisitor {
    var data = ExtractedData()
    
    // Catch state variables
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for attribute in node.attributes {
            if let customAttr = attribute.as(AttributeSyntax.self),
               let attrName = customAttr.attributeName.as(IdentifierTypeSyntax.self)?.name.text {
                if ["State", "Binding", "Environment", "AppStorage", "StateObject", "ObservedObject", "Bindable", "EnvironmentObject"].contains(attrName) {
                    for binding in node.bindings {
                        if let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text {
                            let type = binding.typeAnnotation?.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
                            data.stateVariables.append(StateVariable(name: name, propertyWrapper: attrName, type: type))
                        }
                    }
                }
            }
        }
        return .visitChildren
    }
    
    // Catch if statements
    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        let condition = node.conditions.description.trimmingCharacters(in: .whitespacesAndNewlines)
        var trueElements: [String] = []
        var falseElements: [String] = []
        
        let trueBlock = node.body
        trueElements = extractViews(from: trueBlock)
        
        if let elseBody = node.elseBody {
            if let elseBlock = elseBody.as(CodeBlockSyntax.self) {
                falseElements = extractViews(from: elseBlock)
            } else if let elseIf = elseBody.as(IfExprSyntax.self) {
                falseElements.append("if " + elseIf.conditions.description.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        
        data.conditionals.append(Conditional(condition: condition, trueBranchElements: trueElements, falseBranchElements: falseElements, kind: "if"))
        
        return .visitChildren
    }
    
    // Catch switch statements
    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        let condition = node.subject.description.trimmingCharacters(in: .whitespacesAndNewlines)
        var cases: [String] = []
        for switchCase in node.cases {
            if let caseItem = switchCase.as(SwitchCaseSyntax.self) {
                cases.append(caseItem.label.description.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        data.conditionals.append(Conditional(condition: condition, trueBranchElements: cases, falseBranchElements: [], kind: "switch"))
        return .visitChildren
    }
    
    // Catch ternary operators
    override func visit(_ node: TernaryExprSyntax) -> SyntaxVisitorContinueKind {
        let condition = node.condition.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let trueBranch = node.thenExpression.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let falseBranch = node.elseExpression.description.trimmingCharacters(in: .whitespacesAndNewlines)
        
        data.conditionals.append(Conditional(condition: condition, trueBranchElements: [trueBranch], falseBranchElements: [falseBranch], kind: "ternary"))
        
        return .visitChildren
    }
    
    // Catch compiler directives (#if os(macOS))
    override func visit(_ node: IfConfigDeclSyntax) -> SyntaxVisitorContinueKind {
        for clause in node.clauses {
            let condition = clause.condition?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "else"
            var elements: [String] = []
            if let block = clause.elements?.as(CodeBlockItemListSyntax.self) {
                for item in block {
                    elements.append(item.description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50).description)
                }
            } else {
                elements.append(clause.elements?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            }
            data.compilerDirectives.append(CompilerDirective(condition: condition, elements: elements))
        }
        return .visitChildren
    }
    
    // Catch function calls (modifiers like .opacity, .frame, components like Text, VStack)
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // 1. Check Modifiers (MemberAccessExprSyntax)
        if let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self) {
            let modifierName = memberAccess.declName.baseName.text
            let args = node.arguments.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = memberAccess.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            
            // Hidden Elements
            if modifierName == "opacity" {
                if args == "0" || args == "0.0" {
                    data.hiddenElements.append(HiddenElement(element: base, hidingMethod: "opacity(0)", condition: nil))
                } else if args.contains("?") {
                    data.hiddenElements.append(HiddenElement(element: base, hidingMethod: "opacity(conditional)", condition: args))
                }
            } else if modifierName == "frame" {
                if args.contains("width: 0") || args.contains("height: 0") {
                    data.hiddenElements.append(HiddenElement(element: base, hidingMethod: "hidden frame", condition: args))
                }
            }
            
            // Accessibility Modifiers
            if modifierName.hasPrefix("accessibility") {
                data.accessibilityModifiers.append(Modifier(name: modifierName, arguments: args, base: base))
            }
            
            // Styling Modifiers
            let stylingMods = ["font", "foregroundStyle", "background", "tint", "glassCard", "forestGlass"]
            if stylingMods.contains(modifierName) {
                data.stylingModifiers.append(Modifier(name: modifierName, arguments: args, base: base))
            }
            
            // Layout & Positioning
            let layoutMods = ["frame", "padding", "position", "offset", "zIndex", "gridColumnAlignment"]
            if layoutMods.contains(modifierName) {
                data.layoutModifiers.append(Modifier(name: modifierName, arguments: args, base: base))
            }
            
            // Interactive elements
            if modifierName == "onTapGesture" {
                data.interactiveElements.append(InteractiveElement(type: "onTapGesture", description: "onTapGesture on \(base)"))
            }
        }
        
        // 2. Check view initializers (DeclReferenceExprSyntax)
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = declRef.baseName.text
            let args = node.arguments.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Stack alignments
            if ["VStack", "HStack", "ZStack"].contains(name) {
                if args.contains("alignment:") {
                    data.stackAlignments.append(StackAlignment(stackType: name, alignment: args))
                }
            }
            
            // Hardcoded strings in Text
            if name == "Text" {
                if let firstArg = node.arguments.first?.expression.as(StringLiteralExprSyntax.self) {
                    let text = firstArg.segments.description
                    data.hardcodedStrings.append(HardcodedString(text: text))
                }
            }
            
            // Interactive elements
            if ["Button", "Toggle", "Slider"].contains(name) {
                data.interactiveElements.append(InteractiveElement(type: name, description: "\(name) with args: \(args)"))
            }
        }
        
        return .visitChildren
    }
    
    private func extractViews(from block: CodeBlockSyntax) -> [String] {
        var views: [String] = []
        for item in block.statements {
            let desc = item.item.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstWord = desc.split(separator: "(").first?.split(separator: "{").first?.trimmingCharacters(in: .whitespacesAndNewlines) {
                // VERY rough heuristic: if it starts with a capital letter, it's a View
                if let firstChar = firstWord.first, firstChar.isUppercase {
                    views.append(String(firstWord))
                } else {
                    views.append(String(desc.prefix(50))) // Store a snippet for debugging or non-standard views
                }
            }
        }
        return views
    }
}

@main
struct UIParser {
    static func main() throws {
        guard CommandLine.arguments.count > 1 else {
            print("Usage: ui_parser <file_path>")
            exit(1)
        }
        
        let filePath = CommandLine.arguments[1]
        let fileURL = URL(fileURLWithPath: filePath)
        let source = try String(contentsOf: fileURL, encoding: .utf8)
        
        let sourceFile = Parser.parse(source: source)
        let visitor = ViewVisitor(viewMode: .sourceAccurate)
        visitor.walk(sourceFile)
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(visitor.data)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print(jsonString)
        }
    }
}
