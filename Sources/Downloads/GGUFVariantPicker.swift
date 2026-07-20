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

// MARK: - GGUF Variant

/// A parsed GGUF variant from a repository's sibling list.
///
/// Extracts quantization type, quality tier, and file size from the
/// filename pattern (e.g., `model-Q4_K_M.gguf` → tier: `.recommended`, quant: "Q4_K_M").
struct GGUFVariant: Identifiable, Sendable {
    let id: String
    let filename: String
    let quantization: String
    let sizeBytes: Int64?
    let tier: QualityTier
    let isRecommended: Bool

    /// Quality tier for grouping variants in the picker.
    enum QualityTier: Int, Comparable, Sendable {
        case maximum = 0    // BF16, F16, Q8_0
        case recommended = 1 // Q5_K_M, Q4_K_M, Q4_K_S, Q6_K
        case compact = 2     // Q3_K_M, Q3_K_S, Q2_K, IQ variants

        static func < (lhs: QualityTier, rhs: QualityTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .maximum: return "Maximum Quality"
            case .recommended: return "Recommended Balance"
            case .compact: return "Compact"
            }
        }

        var starRating: String {
            switch self {
            case .maximum: return "★★★"
            case .recommended: return "★★"
            case .compact: return "★"
            }
        }

        var symbolName: String {
            switch self {
            case .maximum: return "star.fill"
            case .recommended: return "star.leadinghalf.filled"
            case .compact: return "star"
            }
        }
    }
}

// MARK: - GGUF Variant Logic

/// Pure functions for extracting and sorting GGUF variants from file lists.
enum GGUFVariantLogic {

    /// Extract all GGUF model variants from a list of siblings.
    ///
    /// Filters out companion files (mmproj, MTP, imatrix) and extracts
    /// quantization type from the filename.
    static func extractVariants(from siblings: [HFSibling]) -> [GGUFVariant] {
        siblings.compactMap { sibling -> GGUFVariant? in
            let name = sibling.rfilename.lowercased()
            guard name.hasSuffix(".gguf") else { return nil }

            // Exclude companion files
            guard !name.contains("mmproj"),
                  !name.hasPrefix("mtp"),
                  !name.contains("imatrix") else { return nil }

            let quant = extractQuantization(from: sibling.rfilename)
            let tier = qualityTier(for: quant)
            let isRec = quant.uppercased() == "Q4_K_M"

            return GGUFVariant(
                id: sibling.rfilename,
                filename: sibling.rfilename,
                quantization: quant,
                sizeBytes: sibling.size ?? sibling.lfs?.size,
                tier: tier,
                isRecommended: isRec
            )
        }
        .sorted { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier < rhs.tier }
            // Within tier, sort by size descending (higher quality first)
            return (lhs.sizeBytes ?? 0) > (rhs.sizeBytes ?? 0)
        }
    }

    /// Extract quantization type from a GGUF filename.
    ///
    /// Handles patterns like:
    /// - `model-Q4_K_M.gguf` → "Q4_K_M"
    /// - `model.Q8_0.gguf` → "Q8_0"
    /// - `model-BF16.gguf` → "BF16"
    /// - `model.gguf` → "Unknown"
    static func extractQuantization(from filename: String) -> String {
        let stem = filename
            .replacingOccurrences(of: ".gguf", with: "")

        // Common quantization patterns (ordered by specificity)
        let patterns: [(regex: String, group: Int)] = [
            // Q4_K_M, Q5_K_S, Q3_K_L, etc.
            (#"[_\-\.](Q\d+_K_[SMLX]+)"#, 1),
            // Q8_0, Q4_0, Q4_1, etc.
            (#"[_\-\.](Q\d+_\d+)"#, 1),
            // Q6_K (no suffix)
            (#"[_\-\.](Q\d+_K)"#, 1),
            // BF16, F16, F32
            (#"[_\-\.](BF16|F16|F32)"#, 1),
            // IQ variants
            (#"[_\-\.](IQ\d+_[A-Z]+)"#, 1),
            (#"[_\-\.](IQ\d+_\d+)"#, 1),
        ]

        for (pattern, group) in patterns {
            if let match = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                .firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
               let range = Range(match.range(at: group), in: stem) {
                return String(stem[range]).uppercased()
            }
        }

        return "Unknown"
    }

    /// Determine quality tier from quantization label.
    static func qualityTier(for quantization: String) -> GGUFVariant.QualityTier {
        let upper = quantization.uppercased()

        // Maximum quality tier
        if upper == "BF16" || upper == "F16" || upper == "F32"
            || upper == "Q8_0" || upper == "Q8_1" {
            return .maximum
        }

        // Compact tier
        if upper.hasPrefix("Q2") || upper.hasPrefix("Q3") || upper.hasPrefix("IQ") {
            return .compact
        }

        // Everything else is recommended (Q4, Q5, Q6)
        return .recommended
    }

    /// Whether a picker is needed (more than one variant).
    static func needsPicker(variants: [GGUFVariant]) -> Bool {
        variants.count > 1
    }

    /// Get the recommended default variant.
    static func recommendedVariant(from variants: [GGUFVariant]) -> GGUFVariant? {
        variants.first(where: { $0.isRecommended }) ?? variants.first(where: { $0.tier == .recommended }) ?? variants.first
    }
}

// MARK: - GGUF Variant Picker View

/// A picker view for selecting among multiple GGUF quantization variants.
///
/// Groups variants by quality tier with star ratings and file sizes.
/// Pre-selects Q4_K_M as the recommended default.
struct GGUFVariantPicker: View {
    let variants: [GGUFVariant]
    @Binding var selectedVariantId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("Choose Quantization")
                .font(AppTypography.sectionHeader)
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityIdentifier("ggufPicker_header")

            let grouped = Dictionary(grouping: variants) { $0.tier }
            let sortedTiers = grouped.keys.sorted()

            VStack(spacing: 0) { // design-system-exempt: zero spacing for tight packing
                ForEach(sortedTiers, id: \.rawValue) { tier in
                    if let tierVariants = grouped[tier] {
                        tierSection(tier: tier, variants: tierVariants)
                    }
                }
            }
            .glassCard(cornerRadius: AppRadius.lg)
        }
        .accessibilityIdentifier("ggufPicker_root")
    }

    @ViewBuilder
    private func tierSection(tier: GGUFVariant.QualityTier, variants: [GGUFVariant]) -> some View {
        VStack(alignment: .leading, spacing: 0) { // design-system-exempt: zero spacing for tight packing
            // Tier header
            HStack(spacing: AppSpacing.xs) {
                Text(tier.starRating)
                    .font(AppTypography.caption)
                Text(tier.displayName)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.xs)

            ForEach(variants) { variant in
                variantRow(variant)
            }
        }
    }

    private func variantRow(_ variant: GGUFVariant) -> some View {
        let isSelected = selectedVariantId == variant.id

        return Button {
            withAnimation(AppAnimation.quick) {
                selectedVariantId = variant.id
            }
        } label: {
            HStack {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AppColors.accentPrimary : AppColors.textTertiary)
                    .font(AppIconSize.sm)

                // Quantization label
                Text(variant.quantization)
                    .font(AppTypography.captionMedium)
                    .foregroundStyle(isSelected ? AppColors.accentPrimary : AppColors.textPrimary)
                    .frame(width: 80, alignment: .leading) // design-system-exempt: structural layout dimensions

                Spacer()

                // File size
                if let size = variant.sizeBytes {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                // Recommended badge
                if variant.isRecommended {
                    Text("Recommended")
                        .badge(AppColors.accentPrimary)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.accentPrimary.opacity(AppOpacity.faint) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ggufPicker_variant_\(variant.quantization)")
    }
}
