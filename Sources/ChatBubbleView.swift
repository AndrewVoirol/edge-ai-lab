import SwiftUI

// MARK: - Chat Bubble View

/// A reusable chat bubble component that renders a single message
/// in the conversation thread. Handles all message types: user, assistant,
/// system, and tool result messages.
///
/// Features:
/// - Role-based styling (user=right/blue, assistant=left/gray)
/// - Collapsible thinking section with pulsing indicator
/// - Inline tool call chips with expandable details
/// - Per-message benchmark mini-badge
/// - Multimodal attachment previews
struct ChatBubbleView: View {
    let message: ChatMessage
    let enableThinking: Bool

    @State private var showThinking = false
    @State private var expandedToolCall: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Role label
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

            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Role Label

    @ViewBuilder
    private var roleLabel: some View {
        HStack(spacing: 4) {
            switch message.role {
            case .user:
                Image(systemName: "person.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("You")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .assistant:
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                Text("Gemma")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .system:
                Image(systemName: "gear")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("System")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .toolResult:
                Image(systemName: "wrench.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Tool Result")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Timestamp
            Text(message.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Content Bubble

    @ViewBuilder
    private var contentBubble: some View {
        Group {
            if message.content.isEmpty && message.isStreaming {
                // Streaming placeholder
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle()
                            .fill(.secondary)
                            .frame(width: 6, height: 6)
                            .opacity(0.5)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(i) * 0.2),
                                value: message.isStreaming
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .multilineTextAlignment(message.role == .user ? .trailing : .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
        }
        .background(bubbleBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        switch message.role {
        case .user:
            Color.accentColor.opacity(0.2)
        case .assistant:
            Color(.systemGray).opacity(0.15)
        case .system:
            Color.yellow.opacity(0.1)
        case .toolResult:
            Color.orange.opacity(0.1)
        }
    }

    // MARK: - Thinking Section

    @ViewBuilder
    private func thinkingSection(_ thinking: String) -> some View {
        DisclosureGroup(isExpanded: $showThinking) {
            Text(thinking)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse, isActive: message.isStreaming)
                Text("Thinking")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.purple)
                Text("(\(thinking.count) chars)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .tint(.purple)
        .padding(.horizontal, 4)
    }

    // MARK: - Tool Call Chips

    @ViewBuilder
    private var toolCallSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(message.toolCalls) { event in
                toolCallChip(event)
            }
        }
    }

    @ViewBuilder
    private func toolCallChip(_ event: ToolCallEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Chip header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedToolCall == event.id {
                        expandedToolCall = nil
                    } else {
                        expandedToolCall = event.id
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: event.succeeded ? "wrench.fill" : "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(event.succeeded ? .orange : .red)
                    Text(event.toolName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(String(format: "%.0fms", event.durationMs))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: expandedToolCall == event.id ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    (event.succeeded ? Color.orange : Color.red).opacity(0.08)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Expanded details
            if expandedToolCall == event.id {
                VStack(alignment: .leading, spacing: 4) {
                    if !event.arguments.isEmpty {
                        Text("Arguments:")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                        Text(event.arguments)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Result:")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(event.result)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(10)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Attachment Previews

    @ViewBuilder
    private var attachmentPreviews: some View {
        HStack(spacing: 8) {
            ForEach(Array(message.attachments.enumerated()), id: \.offset) { _, attachment in
                switch attachment {
                case .image(let data):
                    #if os(iOS)
                    if let uiImage = UIImage(data: data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #elseif os(macOS)
                    if let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    #endif
                case .audio:
                    HStack(spacing: 4) {
                        Image(systemName: "waveform")
                            .font(.caption)
                        Text("Audio")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    // MARK: - Benchmark Badge

    @ViewBuilder
    private func benchmarkBadge(_ benchmark: ChatMessage.BenchmarkSnapshot) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Image(systemName: "speedometer")
                    .font(.system(size: 8))
                Text(String(format: "%.1f tok/s", benchmark.decodeTokensPerSecond))
                    .font(.system(size: 9, design: .monospaced))
            }
            HStack(spacing: 3) {
                Image(systemName: "timer")
                    .font(.system(size: 8))
                Text(String(format: "%.2fs TTFT", benchmark.timeToFirstToken))
                    .font(.system(size: 9, design: .monospaced))
            }
            HStack(spacing: 3) {
                Image(systemName: "number")
                    .font(.system(size: 8))
                Text("\(benchmark.tokenCount) tokens")
                    .font(.system(size: 9, design: .monospaced))
            }
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(.systemGray).opacity(0.06))
        .clipShape(Capsule())
    }
}

// MARK: - Streaming Indicator

/// Animated typing indicator shown while the assistant is generating.
struct StreamingIndicator: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.purple.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .scaleEffect(isAnimating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear { isAnimating = true }
    }
}
