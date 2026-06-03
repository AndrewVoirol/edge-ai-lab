import SwiftUI

// MARK: - Chat Bubble View

/// A premium chat bubble component that renders a single message
/// in the conversation thread. Handles all message types: user, assistant,
/// system, and tool result messages.
///
/// Design: Dark-mode-first with gradient user bubbles, glass assistant bubbles,
/// animated thinking sections, and inline tool call chips with status indicators.
/// Follows Apple's Liquid Glass design language with custom AppColors palette.
///
/// Accessibility: Every interactive element has an `.accessibilityIdentifier`
/// for agent and test discoverability.
struct ChatBubbleView: View {
    let message: ChatMessage
    let enableThinking: Bool

    @State private var showThinking = false
    @State private var expandedToolCall: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            if message.role == .user { Spacer(minLength: 48) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: AppSpacing.sm) {
                // Role label with timestamp
                roleLabel

                // Thinking section (assistant only)
                if message.role == .assistant && enableThinking,
                   let thinking = message.thinkingContent, !thinking.isEmpty {
                    thinkingSection(thinking)
                }

                // Tool call chips (assistant only)
                if message.role == .assistant && !message.toolCalls.isEmpty {
                    toolCallSection
                }

                // Attachment previews (user only)
                if message.role == .user && !message.attachments.isEmpty {
                    attachmentPreviews
                }

                // Message content bubble
                contentBubble

                // Benchmark mini-badge (assistant only)
                if message.role == .assistant, let benchmark = message.benchmarkInfo {
                    benchmarkBadge(benchmark)
                }
            }

            if message.role != .user { Spacer(minLength: 48) }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .messageEntrance()
        .accessibilityIdentifier("chatBubble_\(message.id)")
    }

    // MARK: - Role Label

    @ViewBuilder
    private var roleLabel: some View {
        HStack(spacing: AppSpacing.xs) {
            switch message.role {
            case .user:
                Image(systemName: "person.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentGold)
                Text("You")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            case .assistant:
                Image(systemName: "sparkles")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.accentTeal)
                Text("Gemma")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            case .system:
                Image(systemName: "gear")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textTertiary)
                Text("System")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            case .toolResult:
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.toolCall)
                Text("Tool Result")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            Spacer()

            // Relative timestamp
            Text(message.timestamp, style: .time)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    // MARK: - Content Bubble

    @ViewBuilder
    private var contentBubble: some View {
        Group {
            if message.content.isEmpty && message.isStreaming {
                // Animated streaming indicator
                StreamingIndicator()
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
            } else {
                Text(message.content)
                    .font(AppTypography.body)
                    .foregroundStyle(message.role == .user ? .white : AppColors.textPrimary)
                    .textSelection(.enabled)
                    .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.md)
            }
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.bubble, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.bubble, style: .continuous)
                .stroke(bubbleBorderColor, lineWidth: 0.5)
        )
        .accessibilityIdentifier("messageBubble_\(message.role)")
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            AppGradients.userBubble
        case .assistant:
            AppColors.assistantBubble
        case .system:
            AppColors.backgroundTertiary.opacity(0.6)
        case .toolResult:
            AppColors.toolCall.opacity(0.08)
        }
    }

    private var bubbleBorderColor: Color {
        switch message.role {
        case .user:      return AppColors.userBubbleStart.opacity(0.3)
        case .assistant:  return AppColors.border
        case .system:    return AppColors.warning.opacity(0.15)
        case .toolResult: return AppColors.toolCall.opacity(0.15)
        }
    }

    // MARK: - Thinking Section

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Tap to expand/collapse
            Button {
                withAnimation(AppAnimation.standard) {
                    showThinking.toggle()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "brain.head.profile")
                        .font(.caption)
                        .foregroundStyle(AppColors.thinking)
                        .symbolEffect(.pulse, isActive: message.isStreaming)

                    Text("Reasoning")
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.thinking)

                    Text("·")
                        .foregroundStyle(AppColors.textTertiary)

                    // Word count instead of char count
                    let wordCount = thinking.split(separator: " ").count
                    Text("\(wordCount) words")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    Spacer()

                    Image(systemName: showThinking ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                        .rotationEffect(.degrees(showThinking ? 0 : 0))
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.thinking.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .stroke(AppColors.thinking.opacity(0.1), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("thinkingToggle_\(message.id)")

            // Expanded thinking content
            if showThinking {
                Text(thinking)
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .textSelection(.enabled)
                    .padding(AppSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.thinking.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                        removal: .opacity
                    ))
            }
        }
    }

    // MARK: - Tool Call Chips

    @ViewBuilder
    private var toolCallSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            ForEach(message.toolCalls) { event in
                toolCallChip(event)
            }
        }
    }

    @ViewBuilder
    private func toolCallChip(_ event: ToolCallEvent) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            // Chip header — tap to expand
            Button {
                withAnimation(AppAnimation.standard) {
                    expandedToolCall = expandedToolCall == event.id ? nil : event.id
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    // Status indicator
                    Circle()
                        .fill(event.succeeded ? AppColors.success : AppColors.danger)
                        .frame(width: 6, height: 6)
                        .glow(event.succeeded ? AppColors.success : AppColors.danger, radius: 4, opacity: 0.6)

                    Image(systemName: "wrench.and.screwdriver")
                        .font(.caption2)
                        .foregroundStyle(AppColors.toolCall)

                    Text(event.toolName)
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text(String(format: "%.0fms", event.durationMs))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textTertiary)

                    Image(systemName: expandedToolCall == event.id ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
                .background(AppColors.toolCall.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .stroke(AppColors.toolCall.opacity(0.1), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toolCallChip_\(event.toolName)")

            // Expanded details
            if expandedToolCall == event.id {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    if !event.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Input")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textTertiary)
                            Text(event.arguments)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(AppColors.textSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Output")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textTertiary)
                        Text(event.result)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                            .textSelection(.enabled)
                            .lineLimit(12)
                    }
                }
                .padding(AppSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.backgroundTertiary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    // MARK: - Attachment Previews

    @ViewBuilder
    private var attachmentPreviews: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                switch attachment {
                case .image(let data):
                    #if os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(AppColors.border, lineWidth: 0.5)
                            )
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.md)
                                    .stroke(AppColors.border, lineWidth: 0.5)
                            )
                    }
                    #endif
                case .audio:
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(AppColors.accentTeal)
                        Text("Audio")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(AppColors.accentTeal.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.sm)
                            .stroke(AppColors.accentTeal.opacity(0.12), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    // MARK: - Benchmark Badge

    @ViewBuilder
    private func benchmarkBadge(_ benchmark: ChatMessage.BenchmarkSnapshot) -> some View {
        let tier = PerformanceTier(decodeSpeed: benchmark.decodeTokensPerSecond)

        HStack(spacing: AppSpacing.md) {
            // Decode speed — the hero metric
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(tier.color)
                Text(String(format: "%.1f tok/s", benchmark.decodeTokensPerSecond))
                    .font(AppTypography.metric)
                    .foregroundStyle(tier.color)
            }

            // TTFT
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 8))
                Text(String(format: "%.2fs", benchmark.timeToFirstToken))
                    .font(AppTypography.metric)
            }
            .foregroundStyle(AppColors.textTertiary)

            // Token count
            HStack(spacing: 3) {
                Text("\(benchmark.tokenCount)")
                    .font(AppTypography.metric)
                Text("tok")
                    .font(AppTypography.caption)
            }
            .foregroundStyle(AppColors.textTertiary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(tier.color.opacity(0.06))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(tier.color.opacity(0.1), lineWidth: 0.5)
        )
        .accessibilityIdentifier("benchmarkBadge_\(message.id)")
    }
}

// MARK: - Streaming Indicator

/// Animated typing indicator shown while the assistant is generating.
/// Three dots with staggered pulse animations in the accent teal color.
struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(AppColors.accentTeal.opacity(0.7))
                    .frame(width: 7, height: 7)
                    .scaleEffect(isAnimating ? 1.0 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
        .accessibilityIdentifier("streamingIndicator")
    }
}
