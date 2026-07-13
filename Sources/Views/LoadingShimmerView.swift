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

// MARK: - Loading Shimmer View

/// Animated shimmer placeholder displayed in the chat area while waiting
/// for the first token from the model (pre-TTFT).
///
/// Shows 3 shimmer bars inside an assistant bubble placeholder, creating
/// a skeleton loading state. Critical for the 12B model which has ~14s TTFT.
/// Disables animation under XCTest to prevent runloop saturation.
///
/// Usage:
/// ```swift
/// if isStreaming && response.isEmpty {
///     LoadingShimmerView()
/// }
/// ```
struct LoadingShimmerView: View {
    @State private var shimmerOffset: CGFloat = -200

    /// Cached check: are we running inside an XCTest host?
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CommandLine.arguments.contains("-DisableAnimations")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if Self.isRunningTests || reduceMotion {
            // Static placeholder — no animation cycle to saturate the runloop
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                shimmerBar(width: 200)
                shimmerBar(width: 160)
                shimmerBar(width: 120)
            }
            .accessibilityIdentifier("shimmer_loading")
            .accessibilityLabel("Loading response")
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                shimmerBar(width: 200)
                shimmerBar(width: 160)
                shimmerBar(width: 120)
            }
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
                                AppColors.textTertiary.opacity(0.15), // design-system-exempt: shimmer animation gradient stop
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
/// Disables animation under XCTest to prevent runloop saturation.
struct BlinkingCursor: View {
    @State private var isVisible = true

    /// Cached check: are we running inside an XCTest host?
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CommandLine.arguments.contains("-DisableAnimations")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if Self.isRunningTests || reduceMotion {
            // Static cursor — no animation cycle to saturate the runloop
            Text("▊")
                .font(AppTypography.mono)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityIdentifier("cursor_blinking")
                .accessibilityHidden(true)
        } else {
            Text("▊")
                .font(AppTypography.mono)
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
}

// MARK: - Previews

#Preview("Shimmer Loading") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        LoadingShimmerView()
    }
}

#Preview("Blinking Cursor") {
    ZStack {
        AppColors.backgroundPrimary
            .ignoresSafeArea()
        HStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
            Text("Hello, how can I help")
                .foregroundStyle(AppColors.textPrimary)
            BlinkingCursor()
        }
    }
}
