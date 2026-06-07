import SwiftUI

// MARK: - Loading Shimmer View

/// Animated shimmer placeholder displayed in the chat area while waiting
/// for the first token from the model (pre-TTFT).
///
/// Shows 3 shimmer bars inside an assistant bubble placeholder, creating
/// a skeleton loading state. Critical for the 12B model which has ~14s TTFT.
///
/// Usage:
/// ```swift
/// if isStreaming && response.isEmpty {
///     LoadingShimmerView()
/// }
/// ```
struct LoadingShimmerView: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            // Model avatar placeholder
            Circle()
                .fill(AppColors.backgroundTertiary)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "sparkle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textTertiary)
                }

            // Shimmer bars in bubble shape
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                shimmerBar(width: 200)
                shimmerBar(width: 160)
                shimmerBar(width: 120)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background {
                RoundedRectangle(cornerRadius: AppRadius.bubble)
                    .fill(AppColors.assistantBubble.opacity(0.6))
            }

            Spacer(minLength: 60)
        }
        .padding(.horizontal, AppSpacing.lg)
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                shimmerOffset = 200
            }
        }
        .accessibilityIdentifier("shimmer_loading")
        .accessibilityLabel("Loading response")
    }

    // MARK: - Shimmer Bar

    private func shimmerBar(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.sm)
            .fill(AppColors.backgroundTertiary)
            .frame(width: width, height: 12)
            .overlay {
                RoundedRectangle(cornerRadius: AppRadius.sm)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                AppColors.textTertiary.opacity(0.15),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: shimmerOffset)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }
}

// MARK: - Blinking Cursor

/// A blinking block cursor shown at the end of streaming text.
///
/// Disappears when streaming completes. Uses the app's pulse animation
/// for a consistent feel with other active indicators.
struct BlinkingCursor: View {
    @State private var isVisible = true

    var body: some View {
        Text("▊")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(AppColors.textPrimary)
            .opacity(isVisible ? 1 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                ) {
                    isVisible = false
                }
            }
            .accessibilityIdentifier("cursor_blinking")
            .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Shimmer Loading") {
    ZStack {
        Color(red: 0.06, green: 0.07, blue: 0.10)
            .ignoresSafeArea()
        LoadingShimmerView()
    }
}

#Preview("Blinking Cursor") {
    ZStack {
        Color(red: 0.06, green: 0.07, blue: 0.10)
            .ignoresSafeArea()
        HStack(spacing: 0) {
            Text("Hello, how can I help")
                .foregroundStyle(Color.white)
            BlinkingCursor()
        }
    }
}
