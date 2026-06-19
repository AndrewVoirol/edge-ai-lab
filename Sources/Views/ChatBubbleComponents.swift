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
import MapKit

// MARK: - Streaming Indicator

/// Animated typing indicator shown while the assistant is generating.
/// Three dots with staggered pulse animations in the accent teal color.
/// Disables animation under XCTest to prevent runloop saturation.
struct StreamingIndicator: View {
    @State private var isAnimating = false

    /// Cached check: are we running inside an XCTest host?
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || CommandLine.arguments.contains("-DisableAnimations")

    var body: some View {
        if Self.isRunningTests {
            // Static dots — no animation cycle to saturate the runloop
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(AppColors.accentTeal.opacity(0.7))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityIdentifier("streamingIndicator")
            .accessibilityLabel("Generating response")
        } else {
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
            .accessibilityLabel("Generating response")
        }
    }
}

// MARK: - Wikipedia Summary Card

struct WikipediaSummaryCard: View {
    let title: String
    let extract: String
    let urlString: String
    let thumbnailUrlString: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
                if let urlStr = thumbnailUrlString, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        default:
                            Image(systemName: "book.pages")
                                .font(.largeTitle)
                                .frame(width: 80, height: 80)
                                .background(AppColors.backgroundSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                        }
                    }
                } else {
                    Image(systemName: "book.pages.fill")
                        .font(.largeTitle)
                        .foregroundStyle(AppColors.accentTeal)
                        .frame(width: 80, height: 80)
                        .background(AppColors.accentTeal.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.up.forward.app")
                            .font(.subheadline)
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    Text(extract)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(4)
                }
            }
            
            if let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack {
                        Text("Read full Wikipedia article")
                            .font(.caption)
                            .fontWeight(.medium)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                    }
                    .foregroundStyle(AppColors.accentTeal)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(AppColors.assistantBubble.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wikipedia article: \(title)")
    }
}

// MARK: - Simple Map View

struct SimpleMapView: View {
    let latitude: Double
    let longitude: Double
    let title: String
    let subtitle: String?

    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double, title: String, subtitle: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.subtitle = subtitle
        
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        _position = State(initialValue: .region(MKCoordinateRegion(center: center, span: span)))
    }

    var body: some View {
        Map(position: $position) {
            Marker(title, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Map showing \(title)")
    }
}


// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?
    @State private var copied = false

    private var codeLines: [String] {
        code.components(separatedBy: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(AppTypography.badge)
                        .foregroundStyle(AppColors.accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColors.accentGold.opacity(0.12))
                        .clipShape(Capsule())
                }
                Spacer()
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #else
                    UIPasteboard.general.string = code
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(AppIconSize.xxs)
                        Text(copied ? "Copied" : "Copy")
                            .font(AppTypography.caption)
                    }
                    .foregroundStyle(copied ? AppColors.success : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.2), value: copied)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.25))

            // Divider
            Rectangle()
                .fill(AppColors.border)
                .frame(height: 0.5)

            // Code with line numbers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers gutter
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(codeLines.enumerated()), id: \.offset) { index, _ in
                            Text("\(index + 1)")
                                .font(AppTypography.mono)
                                .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                                .frame(minWidth: 28, alignment: .trailing)
                                .padding(.vertical, 0.5)
                        }
                    }
                    .padding(.leading, AppSpacing.sm)
                    .padding(.trailing, AppSpacing.sm)
                    .background(AppColors.backgroundSecondary.opacity(0.5))

                    // Vertical separator
                    Rectangle()
                        .fill(AppColors.border)
                        .frame(width: 0.5)

                    // Code content
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(codeLines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(AppTypography.mono)
                                .foregroundStyle(AppColors.textPrimary)
                                .textSelection(.enabled)
                                .padding(.vertical, 0.5)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }
                .padding(.vertical, AppSpacing.sm)
            }
        }
        .background(AppColors.backgroundPrimary.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.md)
                .stroke(AppColors.border, lineWidth: 0.5)
        )
        .padding(.vertical, AppSpacing.xs)
    }
}
