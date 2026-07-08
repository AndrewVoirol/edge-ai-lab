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

import SwiftUI

// MARK: - Eval Suite Editor View

/// Editor sheet for creating and editing custom evaluation suites.
///
/// Provides a form for:
/// - Suite name and description
/// - Category selection
/// - Prompt list management (add, edit, delete, reorder)
/// - Expected behavior configuration per prompt
///
/// Used as a sheet from `EvalRunnerView` for both new and editing flows.
struct EvalSuiteEditorView: View {

    // MARK: - Input

    /// The suite to edit, or nil for a new suite.
    let suite: EvalSuite?

    /// Callback when saving completes.
    let onSave: (EvalSuite) -> Void

    /// Callback when cancelling.
    let onCancel: () -> Void

    // MARK: - State

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var category: EvalCategory = .custom
    @State private var prompts: [EditablePrompt] = []
    @State private var editingPromptIndex: Int?

    // MARK: - Editable Prompt

    /// Working model for prompt editing (mutable copy of EvalPrompt fields).
    struct EditablePrompt: Identifiable {
        let id: UUID
        var promptText: String
        var expectedBehavior: ExpectedBehaviorConfig
        var timeoutSeconds: Int

        init(
            id: UUID = UUID(),
            promptText: String = "",
            expectedBehavior: ExpectedBehaviorConfig = .nonEmpty,
            timeoutSeconds: Int = 60
        ) {
            self.id = id
            self.promptText = promptText
            self.expectedBehavior = expectedBehavior
            self.timeoutSeconds = timeoutSeconds
        }

        init(from evalPrompt: EvalPrompt) {
            self.id = evalPrompt.id
            self.promptText = evalPrompt.prompt
            self.timeoutSeconds = evalPrompt.timeoutSeconds
            self.expectedBehavior = ExpectedBehaviorConfig(from: evalPrompt.expectedBehavior)
        }

        func toEvalPrompt() -> EvalPrompt {
            EvalPrompt(
                id: id,
                prompt: promptText,
                expectedBehavior: expectedBehavior.toExpectedBehavior(),
                timeoutSeconds: timeoutSeconds
            )
        }
    }

    // MARK: - Expected Behavior Config

    /// Simplified expected behavior enum for the editor form.
    enum ExpectedBehaviorConfig: Hashable {
        case nonEmpty
        case containsText(String)
        case containsAny([String])
        case containsAll([String])
        case toolCall(String)
        case toolCallWithArgs(String, String, String)
        case toolCallChain([String])
        case matchesRegex(String)
        case codeContains(String, [String])
        case custom(String)

        init(from behavior: ExpectedBehavior) {
            switch behavior {
            case .nonEmpty:
                self = .nonEmpty
            case .containsText(let text):
                self = .containsText(text)
            case .containsAny(let alternatives):
                self = .containsAny(alternatives)
            case .containsAll(let required):
                self = .containsAll(required)
            case .toolCall(toolName: let name):
                self = .toolCall(name)
            case .toolCallWithArgs(toolName: let name, key: let key, expectedValue: let value):
                self = .toolCallWithArgs(name, key, value)
            case .toolCallChain(let chain):
                self = .toolCallChain(chain)
            case .matchesRegex(let pattern):
                self = .matchesRegex(pattern)
            case .codeContains(language: let lang, requiredElements: let elements):
                self = .codeContains(lang, elements)
            case .custom(description: let desc):
                self = .custom(desc)
            }
        }

        func toExpectedBehavior() -> ExpectedBehavior {
            switch self {
            case .nonEmpty:
                return .nonEmpty
            case .containsText(let text):
                return .containsText(text)
            case .containsAny(let alternatives):
                return .containsAny(alternatives)
            case .containsAll(let required):
                return .containsAll(required)
            case .toolCall(let name):
                return .toolCall(toolName: name)
            case .toolCallWithArgs(let name, let key, let value):
                return .toolCallWithArgs(toolName: name, key: key, expectedValue: value)
            case .toolCallChain(let chain):
                return .toolCallChain(chain)
            case .matchesRegex(let pattern):
                return .matchesRegex(pattern)
            case .codeContains(let lang, let elements):
                return .codeContains(language: lang, requiredElements: elements)
            case .custom(let desc):
                return .custom(description: desc)
            }
        }

        var displayName: String {
            switch self {
            case .nonEmpty: return "Non-empty response"
            case .containsText: return "Contains text"
            case .containsAny: return "Contains any of"
            case .containsAll: return "Contains all of"
            case .toolCall: return "Tool call"
            case .toolCallWithArgs: return "Tool call (args)"
            case .toolCallChain: return "Tool chain"
            case .matchesRegex: return "Regex match"
            case .codeContains: return "Code contains"
            case .custom: return "Custom (manual)"
            }
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        EvalSuiteEditorLogic.isValid(
            name: name,
            promptTexts: prompts.map(\.promptText)
        )
    }

    // MARK: - Init

    init(
        suite: EvalSuite?,
        onSave: @escaping (EvalSuite) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.suite = suite
        self.onSave = onSave
        self.onCancel = onCancel
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            titleBar

            Divider().overlay(AppColors.border)

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    // Suite metadata
                    metadataSection

                    // Category picker
                    categoryPicker

                    // Prompts section
                    promptsSection
                }
                .padding(AppSpacing.xl)
            }
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 500, idealHeight: 650)
        .background(AppColors.backgroundPrimary)
        .onAppear {
            loadSuite()
        }
        .accessibilityIdentifier("evalSuiteEditor_root")
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text(suite == nil ? "New Eval Suite" : "Edit Suite")
                .font(AppTypography.sectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            HStack(spacing: AppSpacing.md) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityIdentifier("evalSuiteEditor_cancelButton")

                Button("Save") { saveSuite() }
                    .buttonStyle(.plain)
                    .foregroundStyle(isValid ? AppColors.accentCyan : AppColors.textTertiary)
                    .disabled(!isValid)
                    .accessibilityIdentifier("evalSuiteEditor_saveButton")
            }
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("Suite Details")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            // Name field
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Name")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                TextField("e.g. My Custom Eval", text: $name)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .padding(AppSpacing.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    .accessibilityIdentifier("evalSuiteEditor_nameField")
            }

            // Description field
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Description")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                TextField("What does this suite test?", text: $description, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(3...6)
                    .padding(AppSpacing.sm)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    .accessibilityIdentifier("evalSuiteEditor_descriptionField")
            }
        }
    }

    // MARK: - Category Picker

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Category")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(EvalCategory.allCases, id: \.rawValue) { cat in
                        let isSelected = category == cat

                        Button {
                            withAnimation(AppAnimation.quick) {
                                category = cat
                            }
                        } label: {
                            HStack(spacing: AppSpacing.xs) {
                                Image(systemName: cat.symbolName)
                                    .font(.caption)
                                Text(cat.displayName)
                                    .font(AppTypography.sectionHeader)
                            }
                            .foregroundStyle(
                                isSelected ? AppColors.textPrimary : AppColors.textSecondary
                            )
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .fill(isSelected ? AppColors.accentCyan.opacity(0.15) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(
                                        isSelected ? AppColors.accentCyan.opacity(0.4) : AppColors.border,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("evalSuiteEditor_category_\(cat.rawValue)")
                    }
                }
            }
        }
    }

    // MARK: - Prompts Section

    private var promptsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Text("Prompts")
                    .font(AppTypography.sectionHeader)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                if !prompts.isEmpty {
                    Text("\(prompts.count)")
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.textTertiary)
                }

                Button {
                    addNewPrompt()
                } label: {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Prompt")
                            .font(AppTypography.sectionHeader)
                    }
                    .foregroundStyle(AppColors.accentCyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalSuiteEditor_addPromptButton")
            }

            if prompts.isEmpty {
                emptyPromptsState
            } else {
                ForEach(Array(prompts.enumerated()), id: \.element.id) { idx, prompt in
                    promptRow(index: idx, prompt: prompt)
                }
            }
        }
    }

    private var emptyPromptsState: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "text.bubble")
                .font(AppIconSize.xxl)
                .foregroundStyle(AppColors.textTertiary.opacity(0.5))

            Text("No prompts yet")
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.textSecondary)

            Text("Add prompts to define what this suite evaluates.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)

            Button {
                addNewPrompt()
            } label: {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "plus")
                    Text("Add First Prompt")
                        .font(AppTypography.sectionHeader)
                }
                .foregroundStyle(AppColors.accentCyan)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.accentCyan.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("evalSuiteEditor_addFirstPrompt")
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.xl)
        .glassCard(cornerRadius: AppRadius.lg)
    }

    private func promptRow(index: Int, prompt: EditablePrompt) -> some View {
        let isEditing = editingPromptIndex == index

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Header: index + behavior + actions
            HStack {
                Text("#\(index + 1)")
                    .font(AppTypography.metric)
                    .foregroundStyle(AppColors.accentCyan)

                Text(prompt.expectedBehavior.displayName)
                    .badge(AppColors.accentTeal)

                Text("\(prompt.timeoutSeconds)s")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                Spacer()

                // Edit / collapse
                Button {
                    withAnimation(AppAnimation.quick) {
                        editingPromptIndex = isEditing ? nil : index
                    }
                } label: {
                    Image(systemName: isEditing ? "chevron.up" : "pencil")
                        .font(.caption)
                        .foregroundStyle(AppColors.accentCyan)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalSuiteEditor_editPrompt_\(index)")

                // Delete
                Button {
                    withAnimation(AppAnimation.standard) {
                        if let editing = editingPromptIndex {
                            if editing == index {
                                editingPromptIndex = nil
                            } else if editing > index {
                                editingPromptIndex = editing - 1
                            }
                        }
                        prompts.remove(at: index)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(AppColors.danger)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("evalSuiteEditor_deletePrompt_\(index)")
            }

            // Prompt text (always visible, editable in edit mode)
            if isEditing {
                promptEditForm(index: index)
            } else {
                Text(prompt.promptText.isEmpty ? "Empty prompt" : prompt.promptText)
                    .font(AppTypography.caption)
                    .foregroundStyle(
                        prompt.promptText.isEmpty ? AppColors.textTertiary : AppColors.textSecondary
                    )
                    .lineLimit(2)
            }
        }
        .padding(AppSpacing.md)
        .glassCard(cornerRadius: AppRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(
                    isEditing ? AppColors.accentCyan.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityIdentifier("evalSuiteEditor_promptRow_\(index)")
    }

    @ViewBuilder
    private func promptEditForm(index: Int) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Prompt text
            TextField("Enter prompt text…", text: $prompts[index].promptText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(2...5)
                .padding(AppSpacing.sm)
                .background(AppColors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .accessibilityIdentifier("evalSuiteEditor_promptTextField_\(index)")

            // Expected behavior picker
            HStack(spacing: AppSpacing.md) {
                Text("Expected:")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                behaviorPicker(index: index)
            }

            // Behavior-specific config
            behaviorConfigField(index: index)

            // Timeout
            HStack(spacing: AppSpacing.sm) {
                Text("Timeout:")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)

                TextField("60", value: $prompts[index].timeoutSeconds, format: .number)
                    .textFieldStyle(.plain)
                    .font(AppTypography.mono)
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 50)
                    .padding(.horizontal, AppSpacing.xs)
                    .padding(.vertical, 2)
                    .background(AppColors.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))

                Text("seconds")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func behaviorPicker(index: Int) -> some View {
        let behaviors: [(String, ExpectedBehaviorConfig)] = [
            ("Non-empty", .nonEmpty),
            ("Contains", .containsText("")),
            ("Tool Call", .toolCall("")),
            ("Regex", .matchesRegex("")),
            ("Custom", .custom("")),
        ]

        HStack(spacing: AppSpacing.xs) {
            ForEach(behaviors, id: \.0) { label, behavior in
                let isActive = isSameBehaviorType(prompts[index].expectedBehavior, behavior)

                Button {
                    withAnimation(AppAnimation.quick) {
                        prompts[index].expectedBehavior = behavior
                    }
                } label: {
                    Text(label)
                        .font(AppTypography.badge)
                        .foregroundStyle(isActive ? AppColors.textPrimary : AppColors.textTertiary)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isActive ? AppColors.accentCyan.opacity(0.15) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func behaviorConfigField(index: Int) -> some View {
        switch prompts[index].expectedBehavior {
        case .containsText(let text):
            configTextField(
                label: "Expected text:",
                value: text,
                placeholder: "Text the response should contain",
                index: index,
                update: { prompts[index].expectedBehavior = .containsText($0) }
            )

        case .toolCall(let name):
            configTextField(
                label: "Tool name:",
                value: name,
                placeholder: "e.g. calculate",
                index: index,
                update: { prompts[index].expectedBehavior = .toolCall($0) }
            )

        case .matchesRegex(let pattern):
            configTextField(
                label: "Regex pattern:",
                value: pattern,
                placeholder: "e.g. \\d+\\.?\\d*",
                index: index,
                update: { prompts[index].expectedBehavior = .matchesRegex($0) }
            )

        case .custom(let desc):
            configTextField(
                label: "Description:",
                value: desc,
                placeholder: "What to check manually",
                index: index,
                update: { prompts[index].expectedBehavior = .custom($0) }
            )

        default:
            EmptyView()
        }
    }

    private func configTextField(
        label: String,
        value: String,
        placeholder: String,
        index: Int,
        update: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Text(label)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
                .frame(width: 100, alignment: .trailing)

            TextField(placeholder, text: Binding(
                get: { value },
                set: { update($0) }
            ))
            .textFieldStyle(.plain)
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textPrimary)
            .padding(AppSpacing.xs)
            .background(AppColors.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
            .accessibilityIdentifier("evalSuiteEditor_configField_\(index)")
        }
    }

    // MARK: - Helpers

    private func isSameBehaviorType(
        _ lhs: ExpectedBehaviorConfig,
        _ rhs: ExpectedBehaviorConfig
    ) -> Bool {
        EvalSuiteEditorLogic.isSameBehaviorType(
            lhs.toExpectedBehavior(),
            rhs.toExpectedBehavior()
        )
    }

    private func loadSuite() {
        guard let suite = suite else { return }
        name = suite.name
        description = suite.description
        category = suite.category
        prompts = suite.prompts.map { EditablePrompt(from: $0) }
    }

    private func addNewPrompt() {
        let newPrompt = EditablePrompt()
        withAnimation(AppAnimation.standard) {
            prompts.append(newPrompt)
            editingPromptIndex = prompts.count - 1
        }
    }

    private func saveSuite() {
        let evalPrompts = prompts.map { $0.toEvalPrompt() }
        let savedSuite = EvalSuiteEditorLogic.buildSuite(
            existingSuiteId: suite?.id,
            name: name,
            description: description,
            category: category,
            prompts: evalPrompts,
            existingCreatedAt: suite?.createdAt
        )
        onSave(savedSuite)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Suite Editor — New") {
    EvalSuiteEditorView(
        suite: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Suite Editor — Edit") {
    EvalSuiteEditorView(
        suite: BuiltInEvalSuites.mathAccuracy,
        onSave: { _ in },
        onCancel: {}
    )
}
#endif
