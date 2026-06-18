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

// MARK: - Onboarding View

/// A premium 4-page first-run experience for Edge AI Lab.
///
/// Dark Forest / Moss palette with VibrantBackgroundView, smooth entrance
/// animations, and SF Symbol icons. Presented as a fullScreenCover (iOS)
/// or sheet (macOS) on first launch.
///
/// Accessibility: Every interactive element has `.accessibilityIdentifier`
/// prefixed with `onboarding_` for UI testing and agent discoverability.
struct OnboardingView: View {
    @State private var currentPage = 0
    @State private var appeared = false
    let onComplete: () -> Void

    private let pages = OnboardingPage.allPages

    var body: some View {
        ZStack {
            // Vibrant forest background
            VibrantBackgroundView()
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer()

                // Page content
                pageContent
                    .accessibilityIdentifier("onboarding_page_\(currentPage)")

                Spacer()

                // Page indicator dots
                pageIndicator
                    .padding(.bottom, AppSpacing.xl)

                // Action button
                actionButton
                    .padding(.horizontal, AppSpacing.xxl)
                    .padding(.bottom, AppSpacing.xxl)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
        .overlay(alignment: .topTrailing) {
            // Skip button — visible on pages 0-2 (hidden on the final page)
            if currentPage < pages.count - 1 {
                Button("Skip") {
                    onComplete()
                }
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityIdentifier("button_skipOnboarding")
                .accessibilityHint("Double-tap to skip onboarding")
                .padding(.top, AppSpacing.lg)
                .padding(.trailing, AppSpacing.xl)
            }
        }
        .onAppear {
            withAnimation(AppAnimation.gentleSpring) {
                appeared = true
            }
        }
    }

    // MARK: - Page Content

    private var pageContent: some View {
        let page = pages[currentPage]
        return VStack(spacing: AppSpacing.xl) {
            // SF Symbol icon with glow
            Image(systemName: page.iconName)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(iconColor(for: currentPage))
                .glow(iconColor(for: currentPage), radius: 16, opacity: 0.3)
                .accessibilityIdentifier("onboarding_icon_\(currentPage)")
                .id("icon_\(currentPage)")
                .transition(.scale.combined(with: .opacity))

            // Title
            Text(page.title)
                .font(AppTypography.pageTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding_title_\(currentPage)")
                .id("title_\(currentPage)")

            // Subtitle
            Text(page.subtitle)
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .accessibilityIdentifier("onboarding_subtitle_\(currentPage)")
                .id("subtitle_\(currentPage)")
        }
        .padding(.horizontal, AppSpacing.xxl)
        .animation(AppAnimation.gentleSpring, value: currentPage)
    }

    // MARK: - Page Indicator

    private var pageIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            ForEach(0..<pages.count, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? AppColors.accentCyan : AppColors.textTertiary)
                    .frame(width: index == currentPage ? 10 : 6,
                           height: index == currentPage ? 10 : 6)
                    .animation(AppAnimation.standard, value: currentPage)
                    .accessibilityIdentifier("onboarding_dot_\(index)")
                    .accessibilityHidden(true)
            }
        }
        .accessibilityIdentifier("onboarding_pageIndicator")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Page \(currentPage + 1) of \(pages.count)")
    }

    // MARK: - Action Button

    private var actionButton: some View {
        let isLastPage = currentPage == pages.count - 1
        return Button {
            if isLastPage {
                onComplete()
            } else {
                withAnimation(AppAnimation.gentleSpring) {
                    currentPage += 1
                }
            }
        } label: {
            Text(isLastPage ? "Get Started" : "Continue")
                .font(AppTypography.subtitle)
                .foregroundStyle(AppColors.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background {
                    RoundedRectangle(cornerRadius: AppRadius.xl)
                        .fill(
                            LinearGradient(
                                colors: [AppColors.accentCyan, AppColors.accentTeal],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
        }
        .buttonStyle(.plain)
        .glow(AppColors.accentCyan, radius: 10, opacity: 0.25)
        .accessibilityIdentifier(isLastPage ? "onboarding_getStarted" : "onboarding_continue")
        .accessibilityHint(isLastPage ? "Double-tap to complete setup and start using Edge AI Lab" : "Double-tap to go to next page")
    }

    // MARK: - Helpers

    /// Maps each page index to a distinct accent color from the Dark Forest palette.
    private func iconColor(for index: Int) -> Color {
        switch index {
        case 0: return AppColors.accentCyan
        case 1: return AppColors.accentGold
        case 2: return AppColors.accentTeal
        case 3: return AppColors.accentCyan
        default: return AppColors.accentCyan
        }
    }
}

// MARK: - Preview

#Preview("Onboarding") {
    OnboardingView {
        print("Onboarding completed")
    }
    .preferredColorScheme(.dark)
}
