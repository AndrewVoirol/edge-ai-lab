import SwiftUI

// MARK: - Edge AI Lab Design System
//
// Centralized design tokens for the GemmaEdgeGallery app.
// Follows Apple's Liquid Glass design language (iOS/macOS 26)
// with a premium dark-mode-first aesthetic.

// MARK: - Color Palette

/// Curated color palette — warm golds, cool teals, deep darks.
/// No generic primary colors. Every color is intentional.
enum AppColors {

    // MARK: Backgrounds
    /// The deepest background — near-black with a subtle blue tint.
    static let backgroundPrimary = Color(red: 0.06, green: 0.07, blue: 0.10)
    /// Slightly elevated surface (cards, panels).
    static let backgroundSecondary = Color(red: 0.10, green: 0.11, blue: 0.15)
    /// Tertiary surface (input fields, wells).
    static let backgroundTertiary = Color(red: 0.14, green: 0.15, blue: 0.20)

    // MARK: Accent Gradients
    /// Warm amber/gold for user actions and highlights.
    static let accentGold = Color(red: 0.90, green: 0.72, blue: 0.30)
    /// Cool teal for system/model indicators.
    static let accentTeal = Color(red: 0.20, green: 0.78, blue: 0.78)
    /// Cyan for active/interactive elements.
    static let accentCyan = Color(red: 0.30, green: 0.85, blue: 0.95)

    // MARK: Semantic
    /// Success / ready / healthy.
    static let success = Color(red: 0.30, green: 0.85, blue: 0.50)
    /// Warning / caution.
    static let warning = Color(red: 0.95, green: 0.75, blue: 0.25)
    /// Error / critical / danger.
    static let danger = Color(red: 0.95, green: 0.35, blue: 0.35)
    /// Thinking / reasoning mode.
    static let thinking = Color(red: 0.40, green: 0.65, blue: 0.95)
    /// Tool calling / function execution.
    static let toolCall = Color(red: 0.95, green: 0.60, blue: 0.20)

    // MARK: Text
    /// Primary text — high contrast on dark.
    static let textPrimary = Color(red: 0.93, green: 0.93, blue: 0.96)
    /// Secondary text — labels, captions.
    static let textSecondary = Color(red: 0.60, green: 0.62, blue: 0.68)
    /// Tertiary text — timestamps, hints.
    static let textTertiary = Color(red: 0.40, green: 0.42, blue: 0.48)

    // MARK: Chat Bubbles
    /// User message bubble gradient start.
    static let userBubbleStart = Color(red: 0.18, green: 0.42, blue: 0.78)
    /// User message bubble gradient end.
    static let userBubbleEnd = Color(red: 0.25, green: 0.30, blue: 0.65)
    /// Assistant message bubble.
    static let assistantBubble = Color(red: 0.12, green: 0.13, blue: 0.18)

    // MARK: Borders
    /// Subtle divider/border on dark backgrounds.
    static let border = Color.white.opacity(0.08)
    /// Active/focused border.
    static let borderActive = Color.white.opacity(0.15)
}

// MARK: - Gradients

enum AppGradients {
    /// User chat bubble gradient.
    static let userBubble = LinearGradient(
        colors: [AppColors.userBubbleStart, AppColors.userBubbleEnd],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Header/toolbar gradient.
    static let toolbar = LinearGradient(
        colors: [
            AppColors.backgroundSecondary.opacity(0.95),
            AppColors.backgroundPrimary.opacity(0.98)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Accent shimmer for loading states.
    static let shimmer = LinearGradient(
        colors: [AppColors.accentTeal, AppColors.accentCyan, AppColors.accentTeal],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Thinking mode glow.
    static let thinking = LinearGradient(
        colors: [
            AppColors.thinking.opacity(0.3),
            AppColors.thinking.opacity(0.1),
            AppColors.thinking.opacity(0.3)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Model card background.
    static let card = LinearGradient(
        colors: [
            AppColors.backgroundSecondary,
            AppColors.backgroundTertiary.opacity(0.7)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Typography

enum AppTypography {
    /// Chat message body.
    static let body: Font = .system(.body, design: .default)
    /// Monospaced for code/benchmarks.
    static let mono: Font = .system(.caption, design: .monospaced)
    /// Section headers.
    static let sectionHeader: Font = .system(.subheadline, design: .default, weight: .semibold)
    /// Stats and metrics.
    static let metric: Font = .system(.caption, design: .monospaced, weight: .medium)
    /// Large display numbers (e.g., decode speed).
    static let metricLarge: Font = .system(.title3, design: .monospaced, weight: .bold)
    /// Captions and labels.
    static let caption: Font = .system(.caption2, design: .default)
    /// Tool/badge labels.
    static let badge: Font = .system(.caption2, design: .rounded, weight: .medium)
}

// MARK: - Spacing

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

// MARK: - Corner Radius

enum AppRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    /// Chat bubble.
    static let bubble: CGFloat = 18
    /// Full pill shape.
    static let pill: CGFloat = 100
}

// MARK: - Animations

enum AppAnimation {
    /// Quick micro-interaction.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Standard UI transition.
    static let standard = Animation.easeInOut(duration: 0.25)
    /// Smooth spring for bouncy elements.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// Gentle spring for scroll/layout changes.
    static let gentleSpring = Animation.spring(response: 0.5, dampingFraction: 0.85)
    /// Slow pulse for indicators.
    static let pulse = Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)
    /// Message entrance.
    static let messageEntrance = Animation.spring(response: 0.35, dampingFraction: 0.8)
}

// MARK: - View Modifiers

/// Premium glass card surface.
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = AppRadius.lg

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(AppColors.backgroundSecondary.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(AppColors.border, lineWidth: 0.5)
                    )
            }
    }
}

/// Subtle glow effect behind an element.
struct GlowModifier: ViewModifier {
    let color: Color
    var radius: CGFloat = 12
    var opacity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius, x: 0, y: 0)
    }
}

/// Pulsing glow animation for active indicators.
struct PulsingGlowModifier: ViewModifier {
    let color: Color
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(isPulsing ? 0.5 : 0.15), radius: isPulsing ? 12 : 4)
            .onAppear {
                withAnimation(AppAnimation.pulse) {
                    isPulsing = true
                }
            }
    }
}

/// Entrance animation for chat messages.
struct MessageEntranceModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .onAppear {
                withAnimation(AppAnimation.messageEntrance) {
                    appeared = true
                }
            }
    }
}

/// Badge/pill styling.
struct BadgeModifier: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .font(AppTypography.badge)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - View Extensions

extension View {
    /// Apply premium glass card styling.
    func glassCard(cornerRadius: CGFloat = AppRadius.lg) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }

    /// Add a subtle colored glow.
    func glow(_ color: Color, radius: CGFloat = 12, opacity: Double = 0.4) -> some View {
        modifier(GlowModifier(color: color, radius: radius, opacity: opacity))
    }

    /// Add a pulsing glow animation.
    func pulsingGlow(_ color: Color) -> some View {
        modifier(PulsingGlowModifier(color: color))
    }

    /// Animate entrance (fade + slide up).
    func messageEntrance() -> some View {
        modifier(MessageEntranceModifier())
    }

    /// Style as a colored badge/pill.
    func badge(_ color: Color) -> some View {
        modifier(BadgeModifier(color: color))
    }

    /// Apply the app's dark background.
    func appBackground() -> some View {
        self.background(AppColors.backgroundPrimary)
    }
}

// MARK: - Performance Tier Colors

/// Maps decode speed to a visual tier for instant comprehension.
enum PerformanceTier {
    case excellent  // > 80 tok/s
    case great      // > 40 tok/s
    case good       // > 20 tok/s
    case fair       // > 10 tok/s
    case slow       // <= 10 tok/s

    init(decodeSpeed: Double) {
        switch decodeSpeed {
        case 80...:     self = .excellent
        case 40..<80:   self = .great
        case 20..<40:   self = .good
        case 10..<20:   self = .fair
        default:        self = .slow
        }
    }

    var color: Color {
        switch self {
        case .excellent: return AppColors.accentCyan
        case .great:     return AppColors.success
        case .good:      return AppColors.accentTeal
        case .fair:      return AppColors.warning
        case .slow:      return AppColors.danger
        }
    }

    var label: String {
        switch self {
        case .excellent: return "Blazing"
        case .great:     return "Fast"
        case .good:      return "Good"
        case .fair:      return "Fair"
        case .slow:      return "Slow"
        }
    }
}
